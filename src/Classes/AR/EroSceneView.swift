import ARKit
import CoreML
import Vision

enum SceneMode {
    case Placing(eroNode: EroNode)
    case Interacting
}

public protocol EroSceneDelegate {
    func updateAtTime(time: TimeInterval, delta: Float) -> Void
    func didTouch() -> Void
}

public class EroSceneView: ARSCNView, ARSessionDelegate, ARSCNViewDelegate {
    
    private var mode = SceneMode.Interacting
    
    private var configuration = ARWorldTrackingConfiguration()

    private var currentBuffer: CVPixelBuffer?
    private var previewView: UIImageView?
    
    private var lastUpdateTime: TimeInterval?

    public var eroDelegate: EroSceneDelegate?
    
    private var state = ProgramState()

    override init(frame: CGRect, options: [String : Any]? = nil) {
        super.init(frame: frame, options: options)
        commonInit()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }
    
    convenience init(state: ProgramState) {
        self.init(frame: CGRect.zero)
        self.state = state
    }
    
    private func commonInit() {
        configuration.planeDetection = .horizontal
        configuration.environmentTexturing = .none

        self.autoenablesDefaultLighting = true
        self.automaticallyUpdatesLighting = true
        
        self.session.delegate = self
        self.delegate = self
        self.session.run(configuration)
        
        if DEBUG_HAND_MASK {
            let previewView = UIImageView()
            self.previewView = previewView
            self.addSubview(previewView)
            previewView.translatesAutoresizingMaskIntoConstraints = false
            previewView.bottomAnchor.constraint(equalTo: self.bottomAnchor).isActive = true
            previewView.trailingAnchor.constraint(equalTo: self.trailingAnchor).isActive = true
        }
    }
    
    public func setPlacing(isPlacing: Bool) {
        if isPlacing {
            switch self.mode {
            case .Interacting:
                let newEroNode = EroNode()
                self.mode = .Placing(eroNode: newEroNode)
                self.scene.rootNode.addChildNode(newEroNode)
                
            default: break
            }
        } else {
            switch self.mode {
            case .Placing(let eroNode): eroNode.removeFromParentNode()
            default: break
            }
            mode = SceneMode.Interacting
        }
    }
    
    public func setScaleFactor(scaleFactor: Int) {
        switch self.mode {
        case .Placing(let eroNode):
            eroNode.setScale(scaleFactor: scaleFactor)
            
        default: break
        }
    }
    
    public func place() -> Bool {
        switch self.mode {
        case .Placing(let eroNode):
            if eroNode.isHidden {
                return false
            }
            
            eroNode.physicsBody?.clearAllForces()
            eroNode.reset()
            self.state.eroNodes.append(eroNode)
            self.mode = .Interacting
            return true
            
        default:
            return false
        }
    }
    
    private func positionEroNodeInWorld(eroNode: EroNode, screenLocation: CGPoint) -> Bool {
        let hitTestResults = self.hitTest(screenLocation, types: .existingPlaneUsingExtent)
        guard let hitTestResult = hitTestResults.first else { return false }
    
        eroNode.physicsBody?.clearAllForces()
        eroNode.simdTransform = hitTestResult.worldTransform
        
        let delta = (SCNVector3(eroNode.position.x, 0.0, eroNode.position.z) - SCNVector3(self.pointOfView!.position.x, 0.0, self.pointOfView!.position.z)).normalized();
        let angle = atan2(delta.x, delta.z)
        eroNode.eulerAngles = SCNVector3(0.0, angle + Float.pi / 2, 0.0)
        return true
    }
    
    // MARK: - ARSessionDelegate
    
    public func session(_: ARSession, didUpdate frame: ARFrame) {
        // We return early if currentBuffer is not nil or the tracking state of camera is not normal
        guard currentBuffer == nil, case .normal = frame.camera.trackingState else {
            return
        }
        
        // Retain the image buffer for Vision processing.
        currentBuffer = frame.capturedImage
        
        startDetection()
    }
    
    // MARK: - Private functions
    
    let handDetector = HandDetector()
    
    var debugTouchPointsViews: [UIView] = []
    
    private func startDetection() {
        // To avoid force unwrap in VNImageRequestHandler
        guard let buffer = currentBuffer else { return }
        
        handDetector.performDetection(inputBuffer: buffer) { outputBuffer, _ in
            // Here we are on a background thread
            var previewImage: UIImage?
            var normalizedTouchPoints: [CGPoint] = []
            
            defer {
                DispatchQueue.main.async {
                    self.previewView?.image = previewImage
                    
                    // Release currentBuffer when finished to allow processing next frame
                    self.currentBuffer = nil
                    
                    for view in self.debugTouchPointsViews {
                        view.removeFromSuperview()
                    }
                    
                    if DEBUG_HAND_POINTS {
                        for touchPoint in normalizedTouchPoints {
                            let imageFingerPoint = VNImagePointForNormalizedPoint(touchPoint, Int(self.bounds.size.width), Int(self.bounds.size.height))
                            
                            let myView = UIView(frame: CGRect(x: imageFingerPoint.x, y: imageFingerPoint.y, width: 5, height: 5))
                            myView.backgroundColor = UIColor.red
                            self.addSubview(myView)
                            
                            self.debugTouchPointsViews.append(myView)
                        }
                    }
                    
                    for eroNode in self.state.eroNodes {
                        for touchPoint in normalizedTouchPoints {
                            let imageFingerPoint = VNImagePointForNormalizedPoint(touchPoint, Int(self.bounds.size.width), Int(self.bounds.size.height))
                            let hitTestResults = self.hitTest(imageFingerPoint, options: [
                                SCNHitTestOption.rootNode: eroNode,
                                SCNHitTestOption.searchMode: SCNHitTestSearchMode.any.rawValue
                            ])
                            guard let hitTestResult = hitTestResults.first else { continue }
                            
                            eroNode.touch(from: self.pointOfView!)
                            self.eroDelegate?.didTouch()
                            break
                        }
                    }
                }
            }
            
            guard let outBuffer = outputBuffer else { return }
            
            if self.previewView != nil {
                previewImage = UIImage(ciImage: CIImage(cvPixelBuffer: outBuffer))
            }
            
            normalizedTouchPoints = outBuffer.getTouchPoints(gridSize: 4)
        }
    }
    
    // MARK: - ARSCNViewDelegate
    
    public func renderer(_: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
        guard let _ = anchor as? ARPlaneAnchor else { return nil }
        
        // We return a special type of SCNNode for ARPlaneAnchors
        return PlaneNode()
    }
    
    public func renderer(_: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor,
            let planeNode = node as? PlaneNode else {
                return
        }
        planeNode.update(from: planeAnchor)
    }
    
    public func renderer(_: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        guard let planeAnchor = anchor as? ARPlaneAnchor,
            let planeNode = node as? PlaneNode else {
                return
        }
        planeNode.update(from: planeAnchor)
    }
    
    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let delta: Float = lastUpdateTime == nil ? 1.0 : Float(time - lastUpdateTime!)
        lastUpdateTime = time
    
        switch self.mode {
        case .Placing(let eroNode):
            let couldPlace = positionEroNodeInWorld(
                eroNode: eroNode,
                screenLocation: CGPoint(x: self.frame.width / 2, y: self.frame.height / 2))
            eroNode.isHidden = !couldPlace
            
        default: break
        }
    
        for ball in self.state.eroNodes {
            ball.updateAtTime(time: time, delta: delta)
        }
        
        eroDelegate?.updateAtTime(time: time, delta: delta)
    }
    
    public func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR Error", error)
        self.session.pause()
        self.session.run(configuration, options: [
            .resetTracking,
            .removeExistingAnchors])
    }
}
