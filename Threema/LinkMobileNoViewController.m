//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2012-2021 Threema GmbH
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

#import "LinkMobileNoViewController.h"
#import "MyIdentityStore.h"
#import "ServerAPIConnector.h"
#import <MBProgressHUD/MBProgressHUD.h>
#import "PhoneNumberNormalizer.h"
#import "MDMSetup.h"

@interface LinkMobileNoViewController ()

@end

@implementation LinkMobileNoViewController {
    NSString *mobileNo;
    NSString *prevMobileNo;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    PhoneNumberNormalizer *normalizer = [PhoneNumberNormalizer sharedInstance];
    NSString *examplePhone = [normalizer examplePhoneNumberForRegion:[PhoneNumberNormalizer userRegion]];
    if (examplePhone != nil)
        self.mobileNoTextField.placeholder = examplePhone;
    
    [Colors updateKeyboardAppearanceFor:self.mobileNoTextField];
    
    self.tableView.rowHeight = 85.0;
    self.tableView.estimatedRowHeight = 85.0;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    if ([MyIdentityStore sharedMyIdentityStore].linkedMobileNo != nil) {
        prevMobileNo = [NSString stringWithFormat:@"+%@", [MyIdentityStore sharedMyIdentityStore].linkedMobileNo];
    } else {
        prevMobileNo = @"";
    }
    
    _mobileNoTextField.text = prevMobileNo;
    
    MDMSetup *mdmSetup = [[MDMSetup alloc] initWithSetup:NO];
    if ([mdmSetup readonlyProfile]) {
        _mobileNoTextField.enabled = NO;
    } else {
        [_mobileNoTextField becomeFirstResponder];
    }
}

- (BOOL)shouldAutorotate {
    return YES;
}

-(UIInterfaceOrientationMask)supportedInterfaceOrientations {
    if (SYSTEM_IS_IPAD) {
        return UIInterfaceOrientationMaskAll;
    }
    
    return UIInterfaceOrientationMaskAllButUpsideDown;
}
- (IBAction)cancelAction:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)saveAction:(id)sender {
    if ([self.mobileNoTextField.text isEqualToString:prevMobileNo]) {
        /* no change - nothing to do */
        [self dismissViewControllerAnimated:YES completion:nil];
        return;
    }
    
    /* normalize phone number */
    if (self.mobileNoTextField.text.length > 0) {
        PhoneNumberNormalizer *normalizer = [PhoneNumberNormalizer sharedInstance];
        NSString *prettyMobileNo;
        mobileNo = [normalizer phoneNumberToE164:self.mobileNoTextField.text withDefaultRegion:[PhoneNumberNormalizer userRegion] prettyFormat:&prettyMobileNo];
        if (mobileNo == nil) {
            [UIAlertTemplate showAlertWithOwner:self title:NSLocalizedString(@"bad_phone_number_format_title", nil) message:NSLocalizedString(@"bad_phone_number_format_message", nil) actionOk:nil];
            return;
        }
        
        /* ask user whether our normalization is correct */
        UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"confirm_phone_number_title", nil) message:[NSString stringWithFormat:NSLocalizedString(@"confirm_phone_number_x", nil), prettyMobileNo] preferredStyle:UIAlertControllerStyleAlert];
        [confirmAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"ok", nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * action) {
            [self doLinkMobileNo];
        }]];
        [confirmAlert addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:confirmAlert animated:YES completion:nil];
    } else {
        /* unlink */
        mobileNo = @"";
        [self doLinkMobileNo];
    }
}

- (void)doLinkMobileNo {
    self.navigationItem.rightBarButtonItem.enabled = NO;
    [self.mobileNoTextField resignFirstResponder];
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    
    ServerAPIConnector *conn = [[ServerAPIConnector alloc] init];
    [conn linkMobileNoWithStore:[MyIdentityStore sharedMyIdentityStore] mobileNo:mobileNo onCompletion:^(BOOL linked) {
        [MBProgressHUD hideHUDForView:self.view animated:YES];
        [self dismissViewControllerAnimated:YES completion:nil];
    } onError:^(NSError *error) {
        [MBProgressHUD hideHUDForView:self.view animated:YES];
        self.navigationItem.rightBarButtonItem.enabled = YES;
        
        [UIAlertTemplate showAlertWithOwner:self title:error.localizedDescription message:error.localizedFailureReason actionOk:nil];
    }];
}


#pragma mark - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.tableView.rowHeight;
}

-(CGFloat)tableView:(UITableView *)tableView estimatedHeightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return self.tableView.rowHeight;
}

@end
