//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2013-2021 Threema GmbH
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

#import "AdvancedSettingsViewController.h"
#import "UserSettings.h"
#import "ValidationLogger.h"
#import "NSString+Hex.h"
#import "AppDelegate.h"
#import "AppGroup.h"
#import "ServerConnector.h"
#import "MessageQueue.h"
#import "BundleUtil.h"
#import "ThreemaFramework/ThreemaFramework-swift.h"
#import "ActivityUtil.h"
#import "Utils.h"

#ifdef DEBUG
static const DDLogLevel ddLogLevel = DDLogLevelAll;
#else
static const DDLogLevel ddLogLevel = DDLogLevelNotice;
#endif

@interface AdvancedSettingsViewController ()

@end

@implementation AdvancedSettingsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.validationLoggingSwitch.on = [UserSettings sharedUserSettings].validationLogging;
    self.enableIPv6Switch.on = [UserSettings sharedUserSettings].enableIPv6;
    self.proximityMonitoringSwitch.on = ![UserSettings sharedUserSettings].disableProximityMonitoring;
    self.sentryAppDeviceLabel.text = [UserSettings sharedUserSettings].sentryAppDevice != nil ? [UserSettings sharedUserSettings].sentryAppDevice : @"-";
    self.orphanedFilesCleanupLabel.text = [BundleUtil localizedStringForKey:@"settings_advanced_orphaned_files_cleanup"];
    
    [self.tableView reloadData];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self updateLogSize];
    
    _flushMessageQueueCell.textLabel.text = [BundleUtil localizedStringForKey:@"settings_advanced_flush_message_queue"];
}

- (void)updateLogSize {
    self.logSizeLabel.text = [NSString stringWithFormat:@"%lld KB", ([LogManager logFileSize:[LogManager debugLogFile]] + 1023) / 1024];
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

- (IBAction)enableIPv6Changed:(id)sender {
    [UserSettings sharedUserSettings].enableIPv6 = self.enableIPv6Switch.on;
    [self.tableView reloadData];
    [[ServerConnector sharedServerConnector] reconnect];
}

- (IBAction)validationLoggingChanged:(id)sender {
    [UserSettings sharedUserSettings].validationLogging = self.validationLoggingSwitch.on;
    
    if ([UserSettings sharedUserSettings].validationLogging) {
        [LogManager addFileLogger:[LogManager debugLogFile]];
        
        DDLogNotice(@"Start logging %@", [Utils getClientVersion]);
    }
    else {
        [LogManager removeFileLogger:[LogManager debugLogFile]];
    }
}

- (IBAction)proximityMonitoringChanged:(id)sender {
    [UserSettings sharedUserSettings].disableProximityMonitoring = !self.proximityMonitoringSwitch.on;
    [self.tableView reloadData];
}

#pragma mark - UITableView

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 1) {
        if ([UserSettings sharedUserSettings].disableProximityMonitoring) {
            return NSLocalizedString(@"proximity_monitoring_off", nil);
        } else {
            return NSLocalizedString(@"proximity_monitoring_on", nil);
        }
    } else if (section == 2) {
        return NSLocalizedString(@"validation_logging_expl", nil);
    }
    
    return nil;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
    
    _logSizeLabel.textColor = [Colors fontLight];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (indexPath.section == 2 && indexPath.row == 2) {
        /* share log */
        if ([LogManager logFileSize:[LogManager debugLogFile]] > 0) {
            UIActivityViewController *activityViewController = [ActivityUtil activityViewControllerWithActivityItems:@[[LogManager debugLogFile]] applicationActivities:nil];

            if (SYSTEM_IS_IPAD == YES) {
                
                CGRect rect = [tableView rectForRowAtIndexPath:indexPath];
                activityViewController.popoverPresentationController.sourceRect = rect;
                activityViewController.popoverPresentationController.sourceView = self.view;
            }
            [self presentViewController:activityViewController animated:YES completion:nil];
        } else {
            [UIAlertTemplate showAlertWithOwner:self title:@"" message:NSLocalizedString(@"log_empty_message", nil) actionOk:nil];
        }
    } else if (indexPath.section == 2 && indexPath.row == 3) {
        /* clear log */
        UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"validation_log_clear", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * action) {
            
            [LogManager deleteLogFile:[LogManager debugLogFile]];
            
            [self updateLogSize];
        }]];
        [actionSheet addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
        
        if (!self.tabBarController) {
            CGRect cellRect = [tableView rectForRowAtIndexPath:indexPath];
            actionSheet.popoverPresentationController.sourceRect = cellRect;
            actionSheet.popoverPresentationController.sourceView = self.view;
        }
        
        [self presentViewController:actionSheet animated:YES completion:nil];
        
    }
    else if (indexPath.section == 4 && indexPath.row == 1) {
        [[MessageQueue sharedMessageQueue] flush];
    }
    
    [self.tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
