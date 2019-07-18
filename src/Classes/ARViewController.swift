import ARKit
import CoreML
import Vision

enum ViewMode {
    case Placing
    case Active(vibrationValue: Float)
}

public class ARViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate, EroSceneDelegate {
    
    private var viewMode: ViewMode = ViewMode.Placing
    
    private var sceneView = EroSceneView(state: ProgramState())
    private let changeModeButton = UIButton()
    private let slider = UISlider()

    private var vibratorController: LovenseVibratorController?
    
    lazy var cbManager: CBCentralManager = {
        let manager = CBCentralManager()
        manager.delegate = self
        return manager
    }()
    
    private var peripherals = Set<CBPeripheral>()
    private var state = ProgramState()

    public convenience init(state: ProgramState) {
        self.init()
        self.state = state
        self.sceneView = EroSceneView(state: state)
    }
    
    public override func loadView() {
        super.loadView()
        
        let _ = self.cbManager
        
        view = sceneView
        sceneView.eroDelegate = self
        
        // Navigation controller
        let listButton = UIBarButtonItem()
        listButton.title = "Manage"
        listButton.target = self
        listButton.action = #selector(onListButtonTap)
        self.navigationController?.navigationBar.topItem?.rightBarButtonItems = [listButton]
        
        self.navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        self.navigationController?.navigationBar.shadowImage = UIImage()
        self.navigationController?.navigationBar.isTranslucent = true
        
        // Actions
        let recognizer = UITapGestureRecognizer(target: self, action:#selector(handleTap))
        self.view.addGestureRecognizer(recognizer)
        
        // Slider
        self.view.addSubview(slider)
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -40).isActive = true
        slider.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 20).isActive = true
        slider.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -20).isActive = true
        slider.minimumValue = 1
        slider.maximumValue = 40
        slider.value = 10
        slider.addTarget(self, action: #selector(sliderDidChange), for: .valueChanged)
        sceneView.setScaleFactor(scaleFactor: 10)

        // Mode button
        changeModeButton.addTarget(self, action: #selector(pressModeButton), for: .touchUpInside)
        self.view.addSubview(changeModeButton)
        changeModeButton.translatesAutoresizingMaskIntoConstraints = false
        changeModeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20).isActive = true
        changeModeButton.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true

        changeMode(newMode: ViewMode.Placing)
    }
    
    @objc func handleTap(sender: UITapGestureRecognizer) {
        switch (self.viewMode) {
        case .Placing:
            let _ = sceneView.place()
            changeMode(newMode: .Active(vibrationValue: 0.0))
            
        default: break
        }
    }
    
    @objc func pressModeButton(sender: UIButton) {
        switch (self.viewMode) {
        case .Active: changeMode(newMode: .Placing)
        case .Placing: changeMode(newMode: .Active(vibrationValue: 0.0))
        }
    }
    
    @objc func sliderDidChange(sender: UISlider) {
        sceneView.setScaleFactor(scaleFactor: Int(slider.value))
    }
    
    @objc func onListButtonTap(sender: UIBarButtonItem) {
        self.navigationController?.pushViewController(ListViewController(state: self.state), animated: true)
    }
    
    private func changeMode(newMode: ViewMode) {
        self.viewMode = newMode
        
        switch (newMode) {
        case .Active:
            slider.isHidden = true
            changeModeButton.setTitle("Place", for: UIControl.State.normal)
            sceneView.setPlacing(isPlacing: false)
            return
            
        case .Placing:
            slider.isHidden = false
            changeModeButton.setTitle("Done", for: UIControl.State.normal)
            sceneView.setPlacing(isPlacing: true)

            return
        }
    }
    
    // MARK: - EroSceneDelegate

    public func updateAtTime(time: TimeInterval, delta: Float) {
        switch (self.viewMode) {
        case .Active(let vibrationValue):
            self.viewMode = .Active(vibrationValue: clamp((vibrationValue - delta * 0.35), 0.0, 1.0))
            return
            
        default: return
        }
    }
    
    public func didTouch() {
        switch (self.viewMode) {
        case .Active(let vibrationValue):
            self.viewMode = .Active(vibrationValue: clamp(vibrationValue + 0.05, 0.0, 1.0))

            return
            
        default: return
        }
    }

    // MARK: - CBCentralManagerDelegate
    
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch (central.state) {
        case .poweredOn:
            self.cbManager.scanForPeripherals(
                withServices: (LovenseVibratorController.connectionInfo() as! [LovenseDeviceConnectionInfo]).map({ $0.serviceUUID }),
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            break
            
        default:
            break
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        peripheral.delegate = self
        peripherals.insert(peripheral)
        central.connect(peripheral)
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices((LovenseVibratorController.connectionInfo() as! [LovenseDeviceConnectionInfo]).map({ $0.serviceUUID }))
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        var foundConnectionInfo: LovenseDeviceConnectionInfo?
        for connectionInfo in (LovenseVibratorController.connectionInfo() as! [LovenseDeviceConnectionInfo]) {
            for service in peripheral.services ?? [] {
                if service.uuid.isEqual(connectionInfo.serviceUUID) {
                    foundConnectionInfo = connectionInfo
                    break
                }
            }
        }
        
        if foundConnectionInfo == nil {
            return
        }
        
        LovenseVibratorController.create(with: peripheral, connectionInfo: foundConnectionInfo!, onReady: { (controller, error) -> Void in
            self.vibratorController = controller
            controller!.setVibration(0, onComplete: { (success: Bool, error: Error?) in
                self.vibratorUpdateLoop(controller: controller!, success: true, error: nil)
            })
        })
    }
    
    private func vibratorUpdateLoop(controller: LovenseVibratorController, success: Bool, error: Error?) {
        switch (self.viewMode) {
        case .Active(let vibrationValue):
            controller.setVibration(clamp(UInt32(round(vibrationValue * 20)), UInt32(0), UInt32(20)), onComplete: { (success: Bool, error: Error?) in
                self.vibratorUpdateLoop(controller: controller, success: success, error: error)
            })
            
        default:
            Timer.scheduledTimer(
                withTimeInterval: 0.5,
                 repeats: false,
                 block:  { (Timer) in
                    self.vibratorUpdateLoop(controller: controller, success: true, error: nil)
                })
        }
    }
}
