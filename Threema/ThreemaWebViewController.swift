//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2018-2021 Threema GmbH
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

import UIKit
import ThreemaFramework

class ThreemaWebViewController: ThemedTableViewController {
    
    @IBOutlet weak var cameraButton: UIBarButtonItem!
    
    var entityManager: EntityManager = EntityManager()
    var fetchedResultsController: NSFetchedResultsController<NSFetchRequestResult>?
    var selectedIndexPath: IndexPath?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        fetchedResultsController = entityManager.entityFetcher.fetchedResultsControllerForWebClientSessions()
        fetchedResultsController!.delegate = self
        
        do {
            try fetchedResultsController!.performFetch()
        } catch {
            ErrorHandler.abortWithError(nil)
        }
        
        self.title = NSLocalizedString("webClientSession_title", comment: "")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
                
        let mdmSetup = MDMSetup(setup: false)!
        cameraButton.isEnabled = !mdmSetup.disableWeb()
        
        cleanupWebClientSessions()
        
        cameraButton.image = BundleUtil.imageNamed("QRScan").withTint(Colors.main())
        cameraButton.accessibilityLabel = BundleUtil.localizedString(forKey: "scan_qr")
        
        tableView.reloadData()
    }
    
    // MARK: - Private functions
    
    private func presentActionSheetForSession(_ webClientSession: WebClientSession, indexPath: IndexPath) {
        let alert = UIAlertController(title: NSLocalizedString("webClientSession_actionSheetTitle", comment: ""), message: nil, preferredStyle: .actionSheet)
        
        if (webClientSession.active?.boolValue)! {
            // Stop action
            alert.addAction(UIAlertAction(title: NSLocalizedString("webClientSession_actionSheet_stopSession", comment: ""), style: .default) { stopAction in
                ValidationLogger.shared().logString("Threema Web: Disconnect webclient userStoppedSession")
                WCSessionManager.shared.stopSession(webClientSession)
            })
        } else {
            // Start action
            alert.addAction(UIAlertAction(title: NSLocalizedString("webClientSession_actionSheet_startSession", comment: ""), style: .default) { stopAction in
                ValidationLogger.shared().logString("Threema Web: User start connection")
                WCSessionManager.shared.connect(authToken: nil, wca: nil, webClientSession: webClientSession)
            })
        }
        
        // Rename action
        alert.addAction(UIAlertAction(title: NSLocalizedString("webClientSession_actionSheet_renameSession", comment: ""), style: .default) { _ in
            
            let renameAlert = UIAlertController(title: NSLocalizedString("webClientSession_sessionName", comment: ""), message: nil, preferredStyle: .alert)
            
            renameAlert.addTextField { textfield in
                if let sessionName = webClientSession.name {
                    textfield.text = sessionName
                } else {
                    textfield.placeholder = NSLocalizedString("webClientSession_unnamed", comment: "")
                }
            }
            
            let saveAction = UIAlertAction(title: NSLocalizedString("save", comment: ""), style: .default) { alertAction in
                let textField = renameAlert.textFields![0]
                WebClientSessionStore.shared.updateWebClientSession(session: webClientSession, sessionName: textField.text)
                self.tableView.deselectRow(at: indexPath, animated: true)
            }
            renameAlert.addAction(saveAction)
            
            let cancelAction = UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel) { _ in
                self.tableView.deselectRow(at: indexPath, animated: true)
            }
            renameAlert.addAction(cancelAction)
            
            self.present(renameAlert, animated: true)
        })
               
        // Delete action
        alert.addAction(UIAlertAction(title: NSLocalizedString("webClientSession_actionSheet_deleteSession", comment: ""), style: .destructive) { _ in
            self.deleteWebClientSession(webClientSession)
        })
        
        // Cancel action
        alert.addAction(UIAlertAction(title: NSLocalizedString("cancel", comment: ""), style: .cancel) { _ in
            self.tableView.deselectRow(at: indexPath, animated: true)
        })

        self.present(alert, animated: true)
    }
    
    
    /// Will delete all not persistent sessions where are older then 24 hours and not active
    private func cleanupWebClientSessions() {
        guard let allSessions = entityManager.entityFetcher.allWebClientSessions() as? [WebClientSession] else {
            return
        }
        
        for session in allSessions  {
            if session.permanent?.boolValue == true {
                continue
            }
            
            if let date = session.lastConnection {
                if let diff = Calendar.current.dateComponents([.hour], from: date, to: Date()).hour, diff > 24 {
                    if session.active?.boolValue == false {
                        WebClientSessionStore.shared.deleteWebClientSession(session)
                    }
                }
            }
        }
    }
    
    private func deleteWebClientSession(_ session: WebClientSession) {
        WCSessionManager.shared.stopAndDeleteSession(session)
        
        if fetchedResultsController!.fetchedObjects!.count == 0 {
            UserSettings.shared().threemaWeb = false
        }
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultsController!.sections!.count + 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        }
        
        return fetchedResultsController!.fetchedObjects!.count
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 1 {
            return NSLocalizedString("webClientSession_sessions_header", comment: "")
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 {
            let mdmSetup = MDMSetup(setup: false)!
            if mdmSetup.existsMdmKey(MDM_KEY_DISABLE_WEB) {
                return NSLocalizedString("disabled_by_device_policy", comment: "")
            } else {
                return NSLocalizedString("webClientSession_add_footer", comment: "")
            }
        }
        return nil
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ThreemaWebSettingCell", for: indexPath) as! ThreemaWebSettingCell
            cell.setupCell()
            return cell
        } else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "WebClientSessionCell", for: indexPath) as! WebClientSessionCell
            cell.webClientSession = fetchedResultsController!.fetchedObjects![indexPath.row] as? WebClientSession
            cell.viewController = self
            cell.setupCell()
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, willSelectRowAt indexPath: IndexPath) -> IndexPath? {
        if indexPath.section == 0 && indexPath.row == 0 {
            return nil
        }
        return indexPath
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if indexPath.section == 1 {
            let webClientSession = fetchedResultsController!.fetchedObjects![indexPath.row] as! WebClientSession
            presentActionSheetForSession(webClientSession, indexPath: indexPath)
        }
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let webClientSession = fetchedResultsController!.fetchedObjects![indexPath.row] as! WebClientSession
            deleteWebClientSession(webClientSession)
        }
    }
}

extension ThreemaWebViewController {
    @IBAction func scanNewSession(_ sender: Any?) {
        let qrController = QRScannerViewController()
        qrController.delegate = self
        qrController.title = NSLocalizedString("scan_qr", comment: "")
        let nav = PortraitNavigationController(rootViewController: qrController)
        nav.navigationBar.barStyle = .blackTranslucent
        nav.navigationBar.tintColor = Colors.main()
        nav.modalTransitionStyle = .crossDissolve
        self.present(nav, animated: true)
    }
    
    @IBAction func threemaWebSwitchChanged(_ sender: Any) {
        let threemaWebSwitch = sender as! UISwitch
        UserSettings.shared().threemaWeb = threemaWebSwitch.isOn
        
        if !threemaWebSwitch.isOn {
            // disconnect if there is a active session
            ValidationLogger.shared()?.logString("Threema Web: Disconnect webclient threemaWebOff")
            WCSessionManager.shared.stopAllSessions()
            
            // delete all not saved sessions if it's off
            WCSessionManager.shared.removeAllNotPermanentSessions()
        } else {
            if fetchedResultsController!.fetchedObjects!.count == 0 {
                scanNewSession(nil)
            }
        }
    }
}

extension ThreemaWebViewController: QRScannerViewControllerDelegate {
    func qrScannerViewController(_ controller: QRScannerViewController!, didScanResult result: String!) {
        let data = Data(base64Encoded: result)
        if UserSettings.shared().inAppVibrate {
            AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
        }
        
        if UserSettings.shared().threemaWeb == false {
            UserSettings.shared().threemaWeb = true
        }
        
        guard let qrCodeData = data else {
            ValidationLogger.shared().logString("Threema Web: Can't read qr code")
            let alert = UIAlertController(title: NSLocalizedString("webClientSession_add_wrong_qr_title", comment: ""), message: NSLocalizedString("webClientSession_add_wrong_qr_message", comment: ""), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: NSLocalizedString("ok", comment: ""), style: .default))
            
            self.dismiss(animated: true) {
                self.present(alert, animated: true)
            }
            return
        }
        
        func scannedCodeHandler() {
            handleScannedCode(data: qrCodeData) { error in
                if error == false {
                    self.dismiss(animated: true, completion: nil)
                } else {
                    controller.stopRunning()
                }
            }
        }
        
        // Don't enable Threema Web until all contacts have a non-nil feature mask
        let contacts = ContactStore.shared().contactsWithFeatureMaskNil()
        if let nilContacts = contacts, nilContacts.count > 0 {
            ContactStore.shared().updateFeatureMasks(forContacts: nilContacts, onCompletion: {
                scannedCodeHandler()
            }) { error in
                scannedCodeHandler()
            }
        } else {
            scannedCodeHandler()
        }
    }
    
    func qrScannerViewControllerDidCancel(_ controller: QRScannerViewController!) {
        self.dismiss(animated: true)
    }
    
    private func handleScannedCode(data: Data, completion: @escaping (_ error: Bool?) -> Void) {
        do {
            let format = String(format: ">HB32B32B32BH%is", (data.count) - 101)
            let a = try unpack(format, data)
            
            let allOptions = Bitfield(rawValue: a[1] as! Int)
            var initiatorPermanentPublicKeyArray = [UInt8]()
            for index in 2...33 {
                initiatorPermanentPublicKeyArray.append(UInt8(a[index] as! Int))
            }
            var authTokenArray = [UInt8]()
            for index in 34...65 {
                authTokenArray.append(UInt8(a[index] as! Int))
            }
            var serverPermanentPublicKeyArray = [UInt8]()
            for index in 66...97 {
                serverPermanentPublicKeyArray.append(UInt8(a[index] as! Int))
            }
            
            let scanController = ScanIdentityController()
            scanController.playSuccessSound()
            
            var session = [String: Any]()
            session.updateValue(a[0] as! Int, forKey: "webClientVersion")
            session.updateValue(allOptions.contains(.permanent) ? true : false, forKey: "permanent")
            session.updateValue(allOptions.contains(.selfHosted) ? true : false, forKey: "selfHosted")
            session.updateValue(Data(initiatorPermanentPublicKeyArray), forKey: "initiatorPermanentPublicKey")
            session.updateValue(Data(serverPermanentPublicKeyArray), forKey: "serverPermanentPublicKey")
            session.updateValue((a[98] as! Int), forKey: "saltyRTCPort")
            session.updateValue(a[99] as! NSString, forKey: "saltyRTCHost")
            
            if LicenseStore.requiresLicenseKey() == true {
                let mdmSetup = MDMSetup(setup: false)!
                if let webHosts = mdmSetup.webHosts() {
                    if WCSessionManager.isWebHostAllowed(scannedHostName: session["saltyRTCHost"] as! String, whiteList: webHosts) == false {
                        ValidationLogger.shared().logString("Threema Web: Scanned qr code host is not white listed")
                        let topViewController = AppDelegate.shared()?.currentTopViewController()
                        UIAlertTemplate.showAlert(owner: topViewController!, title: BundleUtil.localizedString(forKey: "webClient_scan_error_mdm_host_title"), message: BundleUtil.localizedString(forKey: "webClient_scan_error_mdm_host_message")) { (action) in
                            self.dismiss(animated: true, completion: nil)
                        }
                        completion(true)
                        return
                    }
                }
            }
            
            ValidationLogger.shared().logString("Threema Web: Scanned qr code")
            
            let webClientSession = WebClientSessionStore.shared.addWebClientSession(dictionary: session)
            
            WCSessionManager.shared.connect(authToken: Data(authTokenArray), wca: nil, webClientSession: webClientSession)
            completion(false)
        } catch {
            ValidationLogger.shared().logString("Threema Web: Can't read qr code")
            completion(false)
        }
    }
    
    
}

struct Bitfield: OptionSet {
    let rawValue: Int
    
    static let selfHosted = Bitfield(rawValue: 1 << 0)
    static let permanent = Bitfield(rawValue: 1 << 1)
}

extension ThreemaWebViewController: NSFetchedResultsControllerDelegate {
    
    public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        tableView.reloadData()
    }

    @nonobjc public func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        tableView.reloadData()
    }
        
    public func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
         tableView.reloadData()
    }
}

