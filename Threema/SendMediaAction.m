//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2015-2021 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

#import "SendMediaAction.h"

#import <MobileCoreServices/MobileCoreServices.h>

#import "UserSettings.h"
#import "AppDelegate.h"
#import "Threema-Swift.h"
#import <Photos/Photos.h>
#import "ModalPresenter.h"
#import "UIDefines.h"
#import "FileMessageSender.h"
#import <MBProgressHUD/MBProgressHUD.h>
#import "BundleUtil.h"
#import "UTIConverter.h"
#import "MediaConverter.h"
#import "MessageSender.h"

#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif
@interface SendMediaAction () <UINavigationControllerDelegate, UIImagePickerControllerDelegate, UIVideoEditorControllerDelegate, UploadProgressDelegate, VideoConversionProgressDelegate>

@property UIImagePickerController *picker;
@property BOOL pickedVideoSent;
@property BOOL pickedVideoSaved;
@property BOOL cancelled;
@property NSURL *pickedVideoURL;
@property NSMutableSet *videoEncoders;
@property NSMutableSet *fileMessageSenders;
@property MBProgressHUD *videoEncodeProgressHUD;
@property PhotosAccessHelper *helper;
@property NSTimer *sequentialSendTimer;

@property dispatch_semaphore_t sequentialSema;

@end

@implementation SendMediaAction

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.videoEncoders = [NSMutableSet set];
        self.fileMessageSenders = [NSMutableSet set];
    }
    return self;
}

- (NSArray *)diffSelection:(NSArray *)assets fromPreviouslySelected:(NSArray *)prevSelected {
    if (prevSelected == nil) {
        return assets;
    }
    
    NSMutableArray *urlItems = [[NSMutableArray alloc] init];
    for (int i = 0; i < prevSelected.count; i++) {
        if ([MediaPreviewViewController isURLItemWithItem:prevSelected[i]]) {
            [urlItems addObject:prevSelected[i]];
        }
    }
    long selectionCount = assets.count + urlItems.count;
    NSMutableArray *selection = [[NSMutableArray alloc] initWithCapacity:selectionCount];
    for (int i = 0; i < urlItems.count; i++) {
        [selection insertObject:urlItems[i] atIndex:i];
    }
    
    for (long i = 0; i < assets.count; i++) {
        long found = [MediaPreviewViewController containsWithAsset:assets[i] itemList:prevSelected];
        if (found == -1) {
            [selection insertObject:assets[i] atIndex:i + urlItems.count];
        } else {
            [selection insertObject:prevSelected[found] atIndex:i + urlItems.count];
        }
    }
    return selection;
}

- (void)executeAction {
    if (_mediaPickerType == MediaPickerChooseExisting) {
        
        [self showPhotoPicker:nil];
        
    } else if (_mediaPickerType == MediaPickerTakePhoto) {
        _picker = [[UIImagePickerController alloc] init];
        _picker.delegate = self;
        
        if (_mediaPickerType == MediaPickerChooseExisting)
            _picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        else
            _picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        
        NSMutableArray *myMediaTypes = [NSMutableArray array];
        NSArray *availableMediaTypes = [UIImagePickerController availableMediaTypesForSourceType:_picker.sourceType];
        if ([availableMediaTypes containsObject:(NSString *)kUTTypeImage]) {
            [myMediaTypes addObject:(NSString *)kUTTypeImage];
        }
        if ([availableMediaTypes containsObject:(NSString *)kUTTypeMovie]) {
            [myMediaTypes addObject:(NSString *)kUTTypeMovie];
        }
        _picker.mediaTypes = myMediaTypes;
        
        _picker.videoMaximumDuration = [MediaConverter videoMaxDurationAtCurrentQuality] * 60;
        
        /* Always request high quality from UIImagePickerController, and transcode by ourselves later */
        _picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
        
        UIImagePickerControllerCameraFlashMode flashmode = UIImagePickerControllerCameraFlashModeAuto;
        if ([[[[AppGroup userDefaults] dictionaryRepresentation] allKeys] containsObject:@"cameraFlashMode"]) {
            flashmode = (UIImagePickerControllerCameraFlashMode) [[AppGroup userDefaults] integerForKey:@"cameraFlashMode"];
        }
        _picker.cameraFlashMode = flashmode;
        
        CGRect rect = [self.chatViewController.view convertRect:self.chatViewController.chatBar.addButton.frame fromView:self.chatViewController.chatBar];
        [ModalPresenter present:_picker on:self.chatViewController fromRect:rect inView:self.chatViewController.view completion:nil];
    } else {
        DDLogError(@"Invalid MediaPickerType");
    }
}

- (void)showPhotoPicker:(NSArray *)lastSelection {
    
    __block NSArray *prevSelected = [[NSArray alloc] init];
    
    int limit = 50;
    
    _helper = [[PhotosAccessHelper alloc] initWithCompletion:^(NSArray * _Nonnull assets, DKImagePickerController * pickerController) {
        
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MediaShareStoryboard" bundle:nil];
        MediaPreviewViewController *selectionViewController = [storyboard instantiateViewControllerWithIdentifier:@"MediaShareController"];
        
        if (assets.count > 0) {
            if ([assets.firstObject isKindOfClass:DKAsset.class]) {
                UIViewController *dismissable = self.chatViewController.presentedViewController.presentingViewController;
                NSArray *initialSelection = [self diffSelection:assets fromPreviouslySelected:prevSelected];
                
                [selectionViewController initWithMediaWithDataArray:initialSelection delegate:self completion:^(NSArray *selection, BOOL sendAsFile, NSArray *captions) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [dismissable dismissViewControllerAnimated:true completion:nil];
                    });
                    [self sendAssets:selection asFile:sendAsFile withCaptions: captions];
                } returnToMe: ^(NSArray *defaultSelection, NSArray *prevSelection) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [selectionViewController dismissViewControllerAnimated:true completion:nil];
                        prevSelected = [NSMutableArray arrayWithArray:prevSelection];
                        [pickerController setDefaultSelectedAssets:defaultSelection];
                        [((ThreemaImagePickerControllerDefaultUIDelegate *) pickerController.UIDelegate) updateButton];
                    });
                } addMore: ^(NSArray *defaultSelection, NSArray *prevSelection) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [selectionViewController dismissViewControllerAnimated:true completion:nil];
                        prevSelected = [NSMutableArray arrayWithArray:prevSelection];
                        [pickerController setDefaultSelectedAssets:defaultSelection];
                        [((ThreemaImagePickerControllerDefaultUIDelegate *) pickerController.UIDelegate) updateButton];
                    });
                }];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    selectionViewController.modalPresentationStyle = UIModalPresentationOverCurrentContext;
                    [self.chatViewController.presentedViewController presentViewController:selectionViewController animated:YES completion:nil];
                });
                
            } else {
                
                if (lastSelection != nil) {
                    assets = [lastSelection arrayByAddingObjectsFromArray:assets];
                }
                
                [selectionViewController initWithMediaWithDataArray:assets delegate:self completion:^(NSArray *selection, BOOL sendAsFile, NSArray *captions) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [selectionViewController dismissViewControllerAnimated:true completion:nil];
                    });
                    [self sendAssets:selection asFile:sendAsFile withCaptions: captions];
                } returnToMe: ^(__unused NSArray *defaultSelection, NSArray *prevSelection) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [selectionViewController dismissViewControllerAnimated:true completion:nil];
                    });
                    [self clearTemporaryDirectoryItems:prevSelection];
                } addMore: ^(__unused NSArray *defaultSelection, NSArray *prevSelection) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        prevSelected = [NSMutableArray arrayWithArray:prevSelection];
                        _helper = [[PhotosAccessHelper alloc] initWithCompletion:^(NSArray * _Nonnull defaultAssets, __unused DKImagePickerController *returnedPickerController) {
                            NSArray *newAssets = [prevSelection arrayByAddingObjectsFromArray:defaultAssets];
                            [selectionViewController resetMediaToDataArray:newAssets reloadData:true];
                        }];
                        [_helper showPickerWithViewController:selectionViewController limit:50-prevSelection.count];
                    });
                    
                }];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [selectionViewController setBackIsCancel:true];
                    [self.chatViewController presentViewController:selectionViewController animated:YES completion:nil];
                });
            }
        }
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        [_helper showPickerWithViewController:self.chatViewController limit:limit];
    });
}

- (DKImagePickerController *)setupDKImagePickerController {
    DKImagePickerController *pickerController = [DKImagePickerController new];
    pickerController.assetType = DKImagePickerControllerAssetTypeAllAssets;
    pickerController.showsCancelButton = YES;
    pickerController.showsEmptyAlbums = NO;
    pickerController.allowMultipleTypes = YES;
    pickerController.autoDownloadWhenAssetIsInCloud = YES;
    pickerController.defaultSelectedAssets = @[];
    pickerController.sourceType = DKImagePickerControllerSourceTypePhoto;
    pickerController.maxSelectableCount = 50;
    pickerController.UIDelegate = [[ThreemaImagePickerControllerDefaultUIDelegate alloc] init];
    pickerController.allowsLandscape = YES;
    
    return pickerController;
}

- (void)showAssetPickerWithAssets:(NSArray *)assets {
    DKImagePickerController *pickerController = [self setupDKImagePickerController];
    [self.chatViewController presentViewController:pickerController animated:YES completion:nil];
}

- (void)showPreviewForAssets:(NSArray *)assets {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"MediaShareStoryboard" bundle:nil];
    MediaPreviewViewController *selectionViewController = [storyboard instantiateViewControllerWithIdentifier:@"MediaShareController"];
    
    selectionViewController.backIsCancel = true;
    
    [selectionViewController initWithMediaWithDataArray:assets delegate:self completion:^(NSArray *selection, BOOL sendAsFile, NSArray *captions) {
        [selectionViewController dismissViewControllerAnimated:true completion:nil];
        [self sendAssets:selection asFile:sendAsFile withCaptions: captions];
    } returnToMe: ^(__unused NSArray *defaultSelection, NSArray *prevSelection) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [selectionViewController dismissViewControllerAnimated:true completion:nil];
        });
        [self clearTemporaryDirectoryItems:prevSelection];
    } addMore: ^(NSArray *defaultSelection, NSArray *prevSelection) {
        DKImagePickerController *pickerController = [self setupDKImagePickerController];
        pickerController.defaultSelectedAssets = defaultSelection;
        [selectionViewController presentViewController:pickerController animated:YES completion:nil];
        
        __weak typeof(pickerController) weakPickerController = pickerController;
        
        [pickerController setDidSelectAssets:^(NSArray * __nonnull selectedAssetes) {
            [weakPickerController dismissViewControllerAnimated:true completion:nil];
            NSArray *selection = [self diffSelection:selectedAssetes fromPreviouslySelected:prevSelection];
            [selectionViewController resetMediaToDataArray:selection reloadData:true];
        }];
    }];
    
    [self.chatViewController presentViewController:selectionViewController animated:YES completion:nil];
}

- (void)prepareAssets:(NSArray *)assets withTarget:(NSMutableArray *)itemArray asFile:(bool) sendAsFile {
    for (int i = 0; i < assets.count; i++) {
        @autoreleasepool {
            if ([assets[i] isKindOfClass:PHAsset.class]) {
                PHAsset *asset = assets[i];
                if (asset.mediaType == PHAssetMediaTypeImage) {
                    URLSenderItem *item = [self getSenderItemForImageAsset:asset asFile:sendAsFile];
                    [itemArray addObject:item];
                } else {
                    URLSenderItem *item = [self getSenderItemForVideoAsset:asset asFile:sendAsFile];
                    [itemArray addObject:item];
                }
            } else {
                NSURL *url = assets[i];
                NSString *uti = [UTIConverter utiForFileURL:url];
                if ([UTIConverter conformsToImageType:uti] || [UTIConverter conformsToMovieType:uti]) {
                    URLSenderItem *item = [URLSenderItemCreator getSenderItemFor:url];
                    if (item != nil)  {
                        [itemArray addObject:item];
                    } else {
                        DDLogError(@"Could not create URLSenderItem from media asset");
                    }
                } else {
                    DDLogError(@"Unrecognized media asset");
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *text = NSLocalizedString(@"processing_items_progress", nil);
                [self incrementVideoProgressHUDWithText:text placeholderIncluded:true];
            });
        }
    }
}

- (void)sendItems:(NSMutableArray *)itemArray asFile:(bool)sendAsFile withCaptions:(NSArray *)captions {
    
    long k = itemArray.count;
    
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    _sequentialSema = dispatch_semaphore_create(1);
    
    NSString *correlationID = [ImageURLSenderItemCreator createCorrelationID];
    
    for (long i = 0; i < k; i++) {
        @autoreleasepool {
            dispatch_semaphore_wait(_sequentialSema, DISPATCH_TIME_FOREVER);
            
            FileMessageSender *sender = [[FileMessageSender alloc] init];
            [self.fileMessageSenders addObject:sender];
            
            if (self.cancelled) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self hideVideoEncodeProgressHUD];
                });
                return;
            }
            
            if ([itemArray[i] isKindOfClass:[URLSenderItem class]]) {
                URLSenderItem *item = itemArray[i];
                if (![captions[i] isEqualToString:@""]) {
                    item.caption = captions[i];
                }
                sender.uploadProgressDelegate = self;
                [sender sendItem:item
                  inConversation:self.chatViewController.conversation
                       requestId:nil
                   correlationId:correlationID];
            } else {
                // Video
                AVAsset *item = itemArray[i];
                [self sendVideoAsset:item onCompletion:^{
                    dispatch_semaphore_signal(sema);
                }];
                dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
                
                _sequentialSendTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                                        target:self
                                                                      selector:@selector(checkVideoDone)
                                                                      userInfo:nil
                                                                       repeats:YES];
                
                if (![captions[i] isEqualToString:@""]) {
                    [MessageSender sendMessage:captions[i]
                                inConversation:self.chatViewController.conversation
                                         async:false
                                    quickReply:false
                                     requestId:nil
                                  onCompletion:^(__unused TextMessage *message, __unused Conversation *conv) {
                        ;//nop
                    }];
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *text = NSLocalizedString(@"sending_item", nil);
                [self incrementVideoProgressHUDWithText:text placeholderIncluded:false];
            });
        }
    }
}

- (void)sendAssets:(NSArray *)assets asFile:(bool)sendAsFile withCaptions:(NSArray *)captions {
    
    NSMutableArray *itemArray = [[NSMutableArray alloc] init];
    
    NSString *text = NSLocalizedString(@"processing_items_progress", nil);
    [self showVideoEncodeProgressHUDWithUnitCount:assets.count text:text];
    
    self.videoEncodeProgressHUD.progressObject.totalUnitCount = assets.count;
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(void) {
        [self prepareAssets:assets withTarget:itemArray asFile:sendAsFile];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *text = NSLocalizedString(@"sending_item", nil);
            [self hideVideoEncodeProgressHUD];
            [self showVideoEncodeProgressHUDWithUnitCount:assets.count text:text];
        });
        
        [self sendItems:itemArray asFile:sendAsFile withCaptions:captions];
        
        double delayInSeconds = 1.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self hideVideoEncodeProgressHUD];
        });
        [self clearTemporaryDirectoryItems:assets];
    });
}

- (void)clearTemporaryDirectoryItems: (NSArray *)items {
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT , 0), ^(void){
        DDLogInfo(@"Started clearing items in temporary directory.");
        NSFileManager *defaultManager = NSFileManager.defaultManager;
        NSError *err;
        for (int i = 0; i < items.count; i++) {
            if ([items[i] isKindOfClass:NSURL.class]) {
                [defaultManager removeItemAtURL:items[i] error:&err];
                if (err != nil) {
                    DDLogError(@"Could not clear item in temporary directory. Error: %@", err.description);
                }
            }
        }
    });
}

- (void)checkVideoDone {
    bool done = true;
    for (SDAVAssetExportSession *exportSession in self.videoEncoders) {
        done = exportSession.progress == 1.0;
    }
    if (self.videoEncoders.count == 0 && done) {
        [_sequentialSendTimer invalidate];
    }
}

- (URLSenderItem *)getSenderItemForImageAsset:(PHAsset *)asset asFile:(bool)sendAsFile {
    
    __block URLSenderItem *item;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    PHImageManager *imageManager = [PHImageManager defaultManager];
    
    PHImageRequestOptions *options  = [PHImageRequestOptions new];
    options.networkAccessAllowed = YES;
    options.version = PHImageRequestOptionsVersionCurrent;
    
    [imageManager requestImageDataForAsset:asset options:options resultHandler:^(NSData *imageData, NSString *dataUTI, __unused UIImageOrientation orientation, __unused NSDictionary *info) {
        
        if (imageData) {
            NSArray *resources = [PHAssetResource assetResourcesForAsset:asset];
            NSString *orgFilename = @"File";
            if (resources.count > 0) {
                orgFilename = ((PHAssetResource*)resources[0]).originalFilename;
            }
            if (sendAsFile) {
                item = [URLSenderItem itemWithData:imageData fileName:orgFilename type:dataUTI renderType:@0 sendAsFile:true];
            } else {
                ImageURLSenderItemCreator *itemCreator = [[ImageURLSenderItemCreator alloc] init];
                item = [itemCreator senderItemFrom:imageData uti:dataUTI];
            }
            dispatch_semaphore_signal(sema);
        }
    }];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return item;
}

- (URLSenderItem *)getSenderItemForVideoAsset:(PHAsset *)asset asFile:(bool)sendAsFile {
    PHImageManager *imageManager = [PHImageManager defaultManager];
    
    __block URLSenderItem *senderItem;
    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    
    PHVideoRequestOptions *options  = [PHVideoRequestOptions new];
    options.version = PHVideoRequestOptionsVersionCurrent;
    options.networkAccessAllowed = YES;
    
    [imageManager requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset *videoAsset, __unused AVAudioMix *audioMix, __unused NSDictionary *info) {
        
        VideoURLSenderItemCreator *senderCreator = [[VideoURLSenderItemCreator alloc] init];
        senderItem = [senderCreator senderItemFromAsset:videoAsset];
        dispatch_semaphore_signal(sema);
    }];
    
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    return senderItem;
}

#pragma mark - Image picker controller delegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [self storeFlashConfigurationFor:picker];
    
    if ([[info objectForKey:UIImagePickerControllerMediaType] isEqualToString:(NSString*)kUTTypeImage]) {
        /* image picked */
        UIImage *pickedImage = [info objectForKey:UIImagePickerControllerOriginalImage];
        
        if (picker.sourceType == UIImagePickerControllerSourceTypeCamera && [UserSettings sharedUserSettings].autoSaveMedia) {
            [[AlbumManager shared] saveWithImage:pickedImage];
        }
        
        if (picker.sourceType == UIImagePickerControllerSourceTypePhotoLibrary) {
            /* need to ask for confirmation when picking images from library, as it's much too
             easy to send the wrong picture with one tap */
            PreviewImageViewController *previewVc = [self.chatViewController.storyboard instantiateViewControllerWithIdentifier:@"PreviewImage"];
            previewVc.delegate = self.chatViewController;
            previewVc.image = pickedImage;
            [picker pushViewController:previewVc animated:YES];
        } else {
            NSURL *imageUrl = [PhotosAccessHelper storeImageToTmprDirWithImageData:pickedImage];
            
            NSArray *array = [NSArray arrayWithObject:imageUrl];
            [picker dismissViewControllerAnimated:true completion:^{
                [self showPreviewForAssets:array];
            }];
        }
    } else if ([[info objectForKey:UIImagePickerControllerMediaType] isEqualToString:(NSString*)kUTTypeMovie]) {
        /* video picked */
        _pickedVideoURL = [info objectForKey:UIImagePickerControllerMediaURL];
        
        _pickedVideoSent = NO;
        _pickedVideoSaved = NO;
        if (picker.sourceType == UIImagePickerControllerSourceTypeCamera && [UserSettings sharedUserSettings].autoSaveMedia) {
            [[AlbumManager shared] saveMovieToLibraryWithMovieURL:_pickedVideoURL completionHandler:^(BOOL success) {
                _pickedVideoSaved = YES;
                if (_pickedVideoSent && _pickedVideoSaved)
                    [[NSFileManager defaultManager] removeItemAtURL:_pickedVideoURL error:nil];
            }];
        } else {
            _pickedVideoSaved = YES;
        }
        
        /* check video duration - if this has come from the photo library, the video may be longer than
         videoMaximumDuration (it is not enforced if allowEditing = NO, but we don't want to enable that
         as we don't need the image cropping UI) */
        if ([MediaConverter isVideoDurationValidAtUrl:_pickedVideoURL]) {
            NSArray *array = [NSArray arrayWithObject:_pickedVideoURL];
            [picker dismissViewControllerAnimated:true completion:^{
                [self showPreviewForAssets:array];
            }];
        } else {
            /* video too long - must present editor */
            UIVideoEditorController *videoEditor = [[UIVideoEditorController alloc] init];
            videoEditor.videoQuality = UIImagePickerControllerQualityTypeHigh;
            videoEditor.videoMaximumDuration = [MediaConverter videoMaxDurationAtCurrentQuality] * 60;
            videoEditor.videoPath = [_pickedVideoURL path];
            videoEditor.delegate = self;
            
            [ModalPresenter dismissPresentedControllerOn:self.chatViewController animated:YES completion:^{
                _picker = nil;
                [self.chatViewController presentViewController:videoEditor animated:YES completion:nil];
            }];
        }
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [self storeFlashConfigurationFor:picker];
    [ModalPresenter dismissPresentedControllerOn:self.chatViewController animated:YES completion:^{
        _picker = nil;
    }];
}

- (void)storeFlashConfigurationFor:(UIImagePickerController *) picker {
    if (picker.sourceType == UIImagePickerControllerSourceTypeCamera) {
        UIImagePickerControllerCameraFlashMode flashmode = picker.cameraFlashMode;
        [[AppGroup userDefaults] setInteger:flashmode forKey:@"cameraFlashMode"];
        [[AppGroup userDefaults] synchronize];
    }
}

#pragma mark - Media sending utility functions

- (void)sendPickedImage:(UIImage *)image {
    if (_picker != nil) {
        [ModalPresenter dismissPresentedControllerOn:self.chatViewController animated:YES completion:^{
            _picker = nil;
        }];
    }
    
    if (image == nil) {
        return;
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        ImageURLSenderItemCreator *item = [[ImageURLSenderItemCreator alloc] init];
        URLSenderItem *senderItem = [item senderItemFromImage:image];
        FileMessageSender *sender = [[FileMessageSender alloc] init];
        [sender sendItem:senderItem inConversation:self.chatViewController.conversation requestId:nil];
    });
}


- (void)video:(NSString*)videoPath didFinishSavingWithError:(NSError*)error contextInfo:(void*)contextInfo {
    _pickedVideoSaved = YES;
    if (_pickedVideoSent && _pickedVideoSaved)
        [[NSFileManager defaultManager] removeItemAtURL:_pickedVideoURL error:nil];
}

- (void)sendPickedVideo {
    if (_picker != nil) {
        _picker = nil;
    }
    [self.chatViewController dismissViewControllerAnimated:YES completion:nil];
    
    if (_pickedVideoURL == nil)
        return;
    
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:_pickedVideoURL options:nil];
    [self sendVideoAsset:asset onCompletion:^{
        _pickedVideoSent = YES;
        if (_pickedVideoSent && _pickedVideoSaved)
            [[NSFileManager defaultManager] removeItemAtURL:_pickedVideoURL error:nil];
    }];
}

- (void)sendVideoAsset:(AVAsset*)asset onCompletion:(void(^)(void))onCompletion {
    dispatch_async(dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        VideoURLSenderItemCreator *senderCreator = [[VideoURLSenderItemCreator alloc] init];
        senderCreator.encodeProgressDelegate = self;
        
        SDAVAssetExportSession *exportSession = [senderCreator getExportSessionFor:asset];
        
        if (exportSession == nil) {
            DDLogError(@"VideoURL was nil.");
            return;
        }
        
        [self.videoEncoders addObject:exportSession];
        
        URLSenderItem *senderItem = [senderCreator senderItemFrom:asset on:exportSession];
        
        FileMessageSender *sender = [[FileMessageSender alloc] init];
        sender.uploadProgressDelegate = self;
        
        [sender sendItem:senderItem inConversation:self.chatViewController.conversation requestId:nil];
        
        if (onCompletion != nil) {
            onCompletion();
        }
    });
}

- (void)videoExportSessionWithExportSession:(SDAVAssetExportSession * _Nonnull)exportSession {
    float progress = exportSession.progress;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (progress == 1.0f) {
            [self.videoEncoders removeObject:exportSession];
        }
    });
}

- (void)showVideoEncodeProgressHUDWithUnitCount:(long)unitCount text:(NSString *)text {
    if (self.videoEncodeProgressHUD == nil) {
        [self.chatViewController.chatBar resignFirstResponder];
        self.videoEncodeProgressHUD = [MBProgressHUD showHUDAddedTo:self.chatViewController.view animated:YES];
        self.videoEncodeProgressHUD.mode = MBProgressHUDModeAnnularDeterminate;
        [self.videoEncodeProgressHUD.button setTitle:NSLocalizedString(@"cancel", nil) forState:UIControlStateNormal];
        [self.videoEncodeProgressHUD.button addTarget:self action:@selector(progressHUDCancelPressed) forControlEvents:UIControlEventTouchUpInside];
        
        self.videoEncodeProgressHUD.progressObject = [[NSProgress alloc] init];
        self.videoEncodeProgressHUD.progressObject.totalUnitCount = unitCount;
        
        long current = self.videoEncodeProgressHUD.progressObject.completedUnitCount;
        long total = self.videoEncodeProgressHUD.progressObject.totalUnitCount;
        
        [self updateHUDTextWithCompleted:current total:total text:text];
    }
}

- (void)hideVideoEncodeProgressHUD {
    if (self.videoEncodeProgressHUD != nil) {
        [self.videoEncodeProgressHUD hideAnimated:YES];
        self.videoEncodeProgressHUD = nil;
    }
}

- (void)incrementVideoProgressHUDWithText:(NSString *)text placeholderIncluded:(bool)placeholder {
    if (self.videoEncodeProgressHUD != nil) {
        self.videoEncodeProgressHUD.progressObject.completedUnitCount++;
        long current = self.videoEncodeProgressHUD.progressObject.completedUnitCount;
        long total = self.videoEncodeProgressHUD.progressObject.totalUnitCount;
        
        if (!placeholder) {
            text = [text stringByAppendingString:@" %d/%d"];
        }
        
        [self updateHUDTextWithCompleted:current total:total text:text];
    }
}

- (void)updateHUDTextWithCompleted:(long)completed total:(long)total text:(NSString *)text {
    self.videoEncodeProgressHUD.label.text = [NSString stringWithFormat:text, completed, total];
}

- (void)removeFileMessageSender:(FileMessageSender*)videoMessageSender {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.fileMessageSenders removeObject:videoMessageSender];
    });
}

- (void)progressHUDCancelPressed {
    for (FileMessageSender *fileMessageSender in self.fileMessageSenders) {
        [fileMessageSender uploadShouldCancel];
    }
    for (SDAVAssetExportSession *exportSession in self.videoEncoders) {
        [exportSession cancelExport];
    }
    __unused bool val = [VideoURLSenderItemCreator cleanTemporaryDirectory];
    self.cancelled = true;
}

#pragma mark - Video editor delegate

- (void)videoEditorController:(UIVideoEditorController *)editor didSaveEditedVideoToPath:(NSString *)editedVideoPath {
    
    /* delete original video file */
    [[NSFileManager defaultManager] removeItemAtURL:_pickedVideoURL error:nil];
    
    _pickedVideoURL = [NSURL fileURLWithPath:editedVideoPath];
    
    [self sendPickedVideo];
}

- (void)videoEditorController:(UIVideoEditorController *)editor didFailWithError:(NSError *)error {
    DDLogWarn(@"Video editor failed: %@", error);
    [editor dismissViewControllerAnimated:YES completion:nil];
}

- (void)videoEditorControllerDidCancel:(UIVideoEditorController *)editor {
    [editor dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UploadProgressDelegate

- (void)blobMessageSender:(BlobMessageSender*)blobMessageSender uploadFailedForMessage:(BaseMessage *)message error:(UploadError)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (error == UploadErrorCancelled) {
            return;
        }
        
        NSString *errorTitle = [BundleUtil localizedStringForKey:@"error_sending_failed"];
        NSString *errorMessage = [FileMessageSender messageForError:error];
        
        [UIAlertTemplate showAlertWithOwner:[[AppDelegate sharedAppDelegate] currentTopViewController] title:errorTitle message:errorMessage actionOk:nil];
    });
    
    self.cancelled = true;
    dispatch_semaphore_signal(_sequentialSema);
}

- (void)blobMessageSender:(BlobMessageSender*)blobMessageSender uploadSucceededForMessage:(BaseMessage *)message {
    if ([blobMessageSender isKindOfClass:FileMessageSender.class]) {
        [self removeFileMessageSender:(FileMessageSender*)blobMessageSender];
    }
    
    dispatch_semaphore_signal(_sequentialSema);
}

- (BOOL)blobMessageSenderUploadShouldCancel:(BlobMessageSender*)blobMessageSender {
    return NO;
}

- (void)blobMessageSender:(BlobMessageSender*)blobMessageSender uploadProgress:(NSNumber *)progress forMessage:(BaseMessage *)message {
    if ([blobMessageSender isKindOfClass:FileMessageSender.class]) {
        [self removeFileMessageSender:(FileMessageSender*)blobMessageSender];
    }
}

@end
