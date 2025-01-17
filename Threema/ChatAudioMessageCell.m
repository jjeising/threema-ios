//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2014-2021 Threema GmbH
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

#import "ChatAudioMessageCell.h"
#import "AudioMessage.h"
#import "AudioData.h"
#import "ChatDefines.h"
#import "UserSettings.h"
#import "Utils.h"
#import "UIImage+ColoredImage.h"
#import "MDMSetup.h"

#ifdef DEBUG
  static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
  static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif

@implementation ChatAudioMessageCell {
    UILabel *durationLabel;
    UIImageView *audioIcon;
}

+ (CGFloat)heightForMessage:(BaseMessage*)message forTableWidth:(CGFloat)tableWidth {
    AudioMessage *audioMessage = (AudioMessage*)message;
    NSString *text = [ChatAudioMessageCell displayTextForAudioMessage:audioMessage];
    
    CGSize size = [text boundingRectWithSize:CGSizeMake([ChatMessageCell maxContentWidthForTableWidth:tableWidth] - 25, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName : [ChatMessageCell textFont]} context:nil].size;
    
    size.height = ceilf(size.height);
    
    return MAX(size.height, 34.0f);
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier transparent:(BOOL)transparent
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier transparent:transparent];
    if (self) {
        audioIcon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Microphone"]];
        [self.contentView addSubview:audioIcon];
        
        durationLabel = [[UILabel alloc] init];
        durationLabel.clearsContextBeforeDrawing = NO;
        durationLabel.backgroundColor = [UIColor clearColor];
        durationLabel.numberOfLines = 0;
        durationLabel.lineBreakMode = NSLineBreakByWordWrapping;
        durationLabel.font = [ChatMessageCell textFont];
        [self.contentView addSubview:durationLabel];
    }
    return self;
}

- (void)setupColors {
    [super setupColors];
    
    audioIcon.image = [UIImage imageNamed:@"Microphone" inColor:[Colors fontNormal]];
    
    durationLabel.textColor = [Colors fontNormal];
}

- (void)layoutSubviews {
    CGFloat messageTextWidth;
    if (@available(iOS 11.0, *)) {
        messageTextWidth = [ChatMessageCell maxContentWidthForTableWidth:self.safeAreaLayoutGuide.layoutFrame.size.width];
    } else {
        messageTextWidth = [ChatMessageCell maxContentWidthForTableWidth:self.frame.size.width];
    }
    CGSize textSize = [durationLabel.text boundingRectWithSize:CGSizeMake(messageTextWidth - 25, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName : [ChatMessageCell textFont]} context:nil].size;
    
    textSize.width = ceilf(textSize.width);
    textSize.height = ceilf(textSize.height);
    CGSize size = CGSizeMake(textSize.width + 25, MAX(34.0f, textSize.height));
    [self setBubbleContentSize:size];
    
    [super layoutSubviews];
    
    CGFloat textY = 7;
    if (textSize.height < 34.0)
        textY += (34.0 - textSize.height) / 2;
    
    if (self.message.isOwn.boolValue) {
        durationLabel.frame = CGRectMake(self.contentView.frame.size.width - textSize.width - 20, textY, floor(textSize.width+1), floor(textSize.height+1));
        audioIcon.frame = CGRectMake(self.contentView.frame.size.width - textSize.width - 42, (durationLabel.frame.origin.y + durationLabel.frame.size.height/2) - audioIcon.frame.size.height/2, audioIcon.frame.size.width, audioIcon.frame.size.height);
        self.resendButton.frame = CGRectMake(self.contentView.frame.size.width - size.width - 160.0f - self.statusImage.frame.size.width, 7 + (size.height - 32) / 2, 114, 32);
    } else {
        durationLabel.frame = CGRectMake(46 + self.contentLeftOffset, textY, floor(textSize.width+1), floor(textSize.height+1));
        audioIcon.frame = CGRectMake(23 + self.contentLeftOffset, (durationLabel.frame.origin.y + durationLabel.frame.size.height/2) - audioIcon.frame.size.height/2, audioIcon.frame.size.width, audioIcon.frame.size.height);
    }
    
    self.activityIndicator.frame = audioIcon.frame;
}

- (NSString *)accessibilityLabelForContent {
    NSString *duration = [Utils accessabilityTimeStringForSeconds:((AudioMessage*)self.message).duration.intValue];

    return [NSString stringWithFormat:@"%@, %@", NSLocalizedString(@"audio", nil), duration];
}

- (void)setMessage:(BaseMessage *)newMessage {    
    [super setMessage:newMessage];
    
    [self updateView];
}

- (BOOL)showActivityIndicator {
    return [self showProgressBar] == NO;
}

- (BOOL)showProgressBar {
    return NO;
}

- (void)updateProgress {
    [self updateActivityIndicator];
}

- (void)updateActivityIndicator {
    AudioMessage *audioMessage = (AudioMessage*)self.message;
    
    if (audioMessage.isOwn.boolValue) {
        if (audioMessage.sent.boolValue || audioMessage.sendFailed.boolValue) {
            [self.activityIndicator stopAnimating];
            audioIcon.hidden = NO;
        } else {
            [self.activityIndicator startAnimating];
            audioIcon.hidden = YES;
        }
    } else {
        if (audioMessage.audio != nil) {
            [self.activityIndicator stopAnimating];
            audioIcon.hidden = NO;
        } else {
            if (audioMessage.progress != nil) {
                [self.activityIndicator startAnimating];
                audioIcon.hidden = YES;
            } else {
                [self.activityIndicator stopAnimating];
                audioIcon.hidden = NO;
            }
        }
    }
}

- (void)updateView {
    AudioMessage *audioMessage = (AudioMessage*)self.message;
    
    NSString *displayText = [ChatAudioMessageCell displayTextForAudioMessage:audioMessage];
    
    if (audioMessage.isOwn.boolValue) {
        durationLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        audioIcon.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    } else {
        durationLabel.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
        audioIcon.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    }
    
    [self setNeedsLayout];
    
    durationLabel.text = displayText;
}

- (void)messageTapped:(id)sender {
    [self.chatVc audioMessageTapped:(AudioMessage*)self.message];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (action == @selector(resendMessage:) && self.message.isOwn.boolValue && self.message.sendFailed.boolValue) {
        return YES;
    } else if (action == @selector(deleteMessage:) && self.message.isOwn.boolValue && !self.message.sent.boolValue && !self.message.sendFailed.boolValue) {
        return NO; /* don't allow messages in progress to be deleted */
    } else if (action == @selector(copyMessage:)) {
        return NO;  /* cannot copy audios */
    } else if (action == @selector(shareMessage:)) {
        if (@available(iOS 13.0, *)) {
            MDMSetup *mdmSetup = [[MDMSetup alloc] initWithSetup:false];
            if ([mdmSetup disableShareMedia] == true) {
                return NO;
            }
        }
        return (((AudioMessage*)self.message).audio != nil);  /* can only save downloaded audios */
    } else if (action == @selector(forwardMessage:)) {
        if (@available(iOS 13.0, *)) {
             return (((AudioMessage*)self.message).audio != nil);  /* can only save downloaded audios */
        } else {
            return NO;
        }
    } else {
        return [super canPerformAction:action withSender:sender];
    }
}

- (void)copyMessage:(UIMenuController *)menuController {
}

- (void)resendMessage:(UIMenuController*)menuController {
    DDLogError(@"AudioMessages can not be resent anymore.");
}

+ (NSString*)displayTextForAudioMessage:(AudioMessage*)audioMessage {
    int seconds = audioMessage.duration.intValue;
    
    return [Utils timeStringForSeconds:seconds];
}

- (BOOL)performPlayActionForAccessibility {
    [self messageTapped:self];
    return YES;
}

@end
