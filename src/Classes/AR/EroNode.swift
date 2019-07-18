import SceneKit

struct BoneState {
    public var bone: SCNNode
    public var velocity: SCNVector3
    public var acceleration: SCNVector3
    public var deformation: SCNVector3
    public var starting: SCNVector3
}

func hexStringToUIColor(hexString: String) -> UIColor {
    var cString: String = hexString.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    
    if (cString.hasPrefix("#")) {
        cString.remove(at: cString.startIndex)
    }
    
    if ((cString.count) != 6) {
        return UIColor.gray
    }
    
    var rgbValue:UInt32 = 0
    Scanner(string: cString).scanHexInt32(&rgbValue)
    
    return UIColor(
        red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
        green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
        blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
        alpha: CGFloat(1.0)
    )
}

public class EroNodeColorScheme {
    private static let colorSchemes: [[UIColor]] = [
        [ // Summer
            hexStringToUIColor(hexString: "01dddd"),
            hexStringToUIColor(hexString: "fd8a5e"),
            hexStringToUIColor(hexString: "ff598f")
        ],
        
    ]

    public let headColor: UIColor
    public let shaftColor: UIColor
    public let ballsColor: UIColor

    public init() {
        var colorScheme = Array(EroNodeColorScheme.colorSchemes[Int.random(in: 0...(EroNodeColorScheme.colorSchemes.count - 1))])
        headColor = EroNodeColorScheme.selectRandomColorAndRemove(colorScheme: &colorScheme);
        shaftColor = EroNodeColorScheme.selectRandomColorAndRemove(colorScheme: &colorScheme);
        ballsColor = EroNodeColorScheme.selectRandomColorAndRemove(colorScheme: &colorScheme);
    }
    
    private static func selectRandomColorAndRemove(colorScheme: inout [UIColor]) -> UIColor {
        let pickedHeadColorIndex = Int.random(in:0...(colorScheme.count - 1))
        let value = colorScheme[pickedHeadColorIndex]
        colorScheme.remove(at: pickedHeadColorIndex)
        return value
    }
}


public class EroNode: SCNNode {
    
    private var bones: [BoneState] = []
    private var armature = SCNNode()
    private var balls = SCNNode()
    private var shaft = SCNNode()
    private var head = SCNNode()
    
    public let colorScheme = EroNodeColorScheme()
    
    private var magnitude: Float = 0.0;
    private var scaleFactor: Int = 10
    
    public override init() {
        super.init()
        
        isHidden = true
        
        let scene = SCNScene(named: "scene.scnassets/phallus")

        shaft = (scene?.rootNode.childNode(withName: "Shaft", recursively: true))!
        self.addChildNode(shaft)

        head = (scene?.rootNode.childNode(withName: "Head", recursively: true))!
        self.addChildNode(head)

        balls = (scene?.rootNode.childNode(withName: "Balls", recursively: true))!
        self.addChildNode(balls)

        self.armature = (scene?.rootNode.childNode(withName: "Armature", recursively: true))!
        
        var bone: SCNNode? = armature.childNode(withName: "Bone", recursively: false)
        while bone != nil {
            self.bones.append(BoneState(
                bone: bone!,
                velocity: SCNVector3(),
                acceleration: SCNVector3(),
                deformation: SCNVector3(),
                starting: bone!.eulerAngles));
            bone = bone!.childNodes.first
        }
        
        // Scale armature
        let scale: Float = 0.05
        armature.scale = SCNVector3Make(scale, scale, scale)
        self.addChildNode(armature)

        // Materials
        setMaterial(head, color: self.colorScheme.headColor)
        setMaterial(shaft, color: self.colorScheme.shaftColor)
        setMaterial(balls, color: self.colorScheme.ballsColor)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setMaterial(_ element: SCNNode, color: UIColor) {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        element.geometry?.firstMaterial = material
        
        let waveShader = """
            uniform float u_time;
            uniform float u_magnitude;

            #pragma body
            float magnitude = 0.15;
            float displacement = 1.0 - u_magnitude * magnitude * sin(u_time * 5.0 + _geometry.position.y * 150);
            float verticalStretch = 1.0 + 0.25 * u_magnitude;
            _geometry.position.xyz = _geometry.position.xyz * float3(displacement, 1.0, displacement) * float3(1.0, verticalStretch, 1.0);
        """
        element.geometry?.shaderModifiers = [SCNShaderModifierEntryPoint.geometry: waveShader]
        element.geometry?.materials.first?.setValue(magnitude, forKey: "u_magnitude")
    }
    
    public func setScale(scaleFactor: Int) {
        self.scaleFactor = scaleFactor
        
        let scale: Float = 0.05 * Float(scaleFactor) / 10.0
        armature.scale = SCNVector3Make(scale, scale, scale)
    }
    
    public func reset() {
        for i in 0..<(bones.count) {
            let state = bones[i]
            bones[i] = BoneState(
                bone: state.bone,
                velocity: SCNVector3(),
                acceleration: SCNVector3(),
                deformation: SCNVector3(),
                starting: state.starting
            )
        }
    }
    
    public func touch(from: SCNNode) {
        let maxUpdateVelocity: Float = 6.0
        var delta = (from.position - self.position)
        delta.y = 0;
        delta = delta.normalized() * 1.0 // We only care about the direction
        
        for i in 0..<(bones.count) {
            let state = bones[i]
            
            var velocity = state.velocity + SCNVector3(delta.x, delta.z, 0.0)
            if (velocity.length() > maxUpdateVelocity) {
                velocity *= maxUpdateVelocity / velocity.length();
            }
            
            bones[i] = BoneState(
                bone: state.bone,
                velocity: velocity,
                acceleration: state.acceleration,
                deformation: state.deformation,
                starting: state.starting
            )
        }
        
        magnitude += 0.05
        magnitude = clamp(magnitude, 0.0, 1.0)
    }
    
    public func updateAtTime(time: TimeInterval, delta: Float) {
        let maxAcceleration: Float = 30

        let k: Float = -20 // Spring stiffness
        let b: Float = -2  // Damping constant
        
        let base: Float = 1.0 / Float(bones.count)
        
        var maxVelocity: Float = 0.0
        for i in 0..<(bones.count) {
            let bone = bones[i]
            
            let spring_x = k * bone.deformation.x
            let damper_x = b * bone.velocity.x
            let acceleration_x = spring_x + damper_x
            
            let spring_y = k * bone.deformation.y
            let damper_y = b * bone.velocity.y
            let acceleration_y = spring_y + damper_y
            
            var acceleration = SCNVector3(acceleration_x, acceleration_y, 0.0)
            if acceleration.length() > maxAcceleration {
                acceleration *= maxAcceleration / acceleration.length();
            }
            
            let velocity = bone.velocity + SCNVector3(acceleration_x * delta, acceleration_y * delta, 0)
            
            maxVelocity = max(maxVelocity, Float(velocity.length()))
            
            let deformation = bone.deformation + velocity * delta

            bones[i] = BoneState(
                bone: bone.bone,
                velocity: velocity,
                acceleration: acceleration,
                deformation: deformation,
                starting: bone.starting
            )
            
            bone.bone.eulerAngles = bone.starting + SCNVector3(i == 0 ? 0.0 : base * deformation.x, i == 0 ? 0.0 : base * deformation.y, 0.0)
        }
        
        for element in [shaft, head, balls] {
            element.geometry?.materials.first?.setValue(magnitude, forKey: "u_magnitude")
        }

        magnitude -= 0.35 * delta
        magnitude = clamp(magnitude, 0.0, 1.0)
    }
}

