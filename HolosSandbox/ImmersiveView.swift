import SwiftUI
import RealityKit
import simd
import Combine

// MARK: - Data Structures
struct Pose {
    var transforms: [String: Transform]
}

struct Keyframe {
    var time: TimeInterval
    var pose: Pose
}

// MARK: - Main View
struct ImmersiveView: View {
    @State private var subscription: AnyCancellable?
    @State private var animationPlaying = false
    
    var body: some View {
        RealityView { content in
            do {
                let model = try await ModelEntity(named: "character")
                model.position = [0, 1.2, -2] // Adjusted Y for better viewing
           
                model.scale = [1.0, 1.0, 1.0]
                
                content.add(model)
                
                // Setup animation after a small delay to ensure the scene is ready
                Task {
                    try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
                    await setupAnimation(model: model)
                }
                
            } catch {
                print("Failed to load model: \(error)")
            }
        }
    }
    
    
    private func easeOutBack(_ t: Float) -> Float {
        let c1: Float = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    // Back ease in out - overshoots at both ends
    private func easeInOutBack(_ t: Float) -> Float {
        let c1: Float = 1.70158
        let c2 = c1 * 1.525
        
        if t < 0.5 {
            return (pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2
        } else {
            return (pow(2 * t - 2, 2) * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2
        }
    }

    // Elastic ease out - bouncy overshoot (most dramatic)
    private func easeOutElastic(_ t: Float) -> Float {
        let c4 = (2 * Float.pi) / 3
        
        if t == 0 {
            return 0
        } else if t == 1 {
            return 1
        } else {
            return pow(2, -10 * t) * sin((t * 10 - 0.75) * c4) + 1
        }
    }

    // Custom overshoot - adjustable intensity
    private func easeOutOvershoot(_ t: Float, overshoot: Float = 0.3) -> Float {
        let scaledT = t - 1
        return 1 + (1 + overshoot) * scaledT * scaledT * scaledT + overshoot * scaledT * scaledT
    }
    
    @MainActor
    private func setupAnimation(model: ModelEntity) async {
        guard let scene = model.scene else {
            print("ERROR: Scene not found on model. Retrying in 0.1s.")
            // Retry if the scene isn't ready yet
            Task {
                try await Task.sleep(nanoseconds: 100_000_000)
                await setupAnimation(model: model)
            }
            return
        }
        
        var startingPoseTransforms: [String: Transform] = [:]
        var jointIndices: [String: Int] = [:]
        let requiredJoints = [rightShoulderName, leftShoulderName, rightArmName, rightForearmName, rightHandName, headName]

        for jointName in requiredJoints {
            if let index = model.jointNames.firstIndex(of: jointName) {
                jointIndices[jointName] = index
                // Read the actual transform from the model's default pose
                startingPoseTransforms[jointName] = model.jointTransforms[index]
            }
        }

        if !animationKeyframes.isEmpty {
            animationKeyframes[0].pose = Pose(transforms: startingPoseTransforms)
        }
         
        
        var animationTime: TimeInterval = 0
        
        self.subscription = scene.subscribe(to: SceneEvents.Update.self) { event in
            animationTime += event.deltaTime
            let loopedTime = animationTime.truncatingRemainder(dividingBy: 12)
            
            guard let (prevKeyframe, nextKeyframe) = findKeyframes(for: loopedTime) else { return }
            
            let timeInRange = loopedTime - prevKeyframe.time
            let rangeDuration = nextKeyframe.time - prevKeyframe.time
            // Prevent division by zero if keyframes have the same time
            let linearT = rangeDuration > 0 ? Float(timeInRange / rangeDuration) : 0
            let easedT = easeInOutBack(linearT)
            
            for (jointName, jointIndex) in jointIndices {
                guard let prevTransform = prevKeyframe.pose.transforms[jointName],
                      let nextTransform = nextKeyframe.pose.transforms[jointName] else { continue }
                
                // Interpolate ONLY the rotation.
                let interpolatedRotation = simd_slerp(prevTransform.rotation, nextTransform.rotation, easedT)
                
                // Start with the model's current transform to preserve its position and scale.
                var newTransform = model.jointTransforms[jointIndex]
                newTransform.rotation = interpolatedRotation
                
                model.jointTransforms[jointIndex] = newTransform
            }
            
            print("--- Animation Frame - Time: \(String(format: "%.2f", loopedTime)) ---")
            for (jointName, jointIndex) in jointIndices {
                // 1. Get the current transform directly from the model
                let currentTransform = model.jointTransforms[jointIndex]
                
                // 2. Get the rotation quaternion
                let currentRotation = currentTransform.rotation
                
                // 3. Get the angle (in radians) and axis vector
                let angle = currentRotation.angle
                let axis = currentRotation.axis
                
                // 4. Print the formatted values
                let jointDisplayName = jointName.split(separator: "/").last ?? ""
                print("\(jointDisplayName):")
                print(String(format: "  Angle: %.3f rad", angle))
                print(String(format: "  Axis: [x: %.2f, y: %.2f, z: %.2f]", axis.x, axis.y, axis.z))
            }
        } as! AnyCancellable
        
        animationPlaying = true
        print("Animation started successfully!")
    }

    private func findKeyframes(for time: TimeInterval) -> (Keyframe, Keyframe)? {
        // Ensure keyframes are sorted by time, just in case.
        let sortedKeyframes = animationKeyframes.sorted { $0.time < $1.time }
        
        if time < sortedKeyframes.first?.time ?? 0 {
            return (sortedKeyframes.first!, sortedKeyframes.first!)
        }
        
        for i in 0..<(sortedKeyframes.count - 1) {
            let current = sortedKeyframes[i]
            let next = sortedKeyframes[i + 1]
            if time >= current.time && time <= next.time {
                return (current, next)
            }
        }
        return (sortedKeyframes.last!, sortedKeyframes.last!)
    }
}

// MARK: - Joint Names
let rightShoulderName = "root/hips_joint/spine_1_joint/spine_2_joint/spine_3_joint/spine_4_joint/spine_5_joint/spine_6_joint/spine_7_joint/right_shoulder_1_joint"
let leftShoulderName = "root/hips_joint/spine_1_joint/spine_2_joint/spine_3_joint/spine_4_joint/spine_5_joint/spine_6_joint/spine_7_joint/left_shoulder_1_joint"
let rightArmName = "root/hips_joint/spine_1_joint/spine_2_joint/spine_3_joint/spine_4_joint/spine_5_joint/spine_6_joint/spine_7_joint/right_shoulder_1_joint/right_arm_joint"
let rightForearmName = "root/hips_joint/spine_1_joint/spine_2_joint/spine_3_joint/spine_4_joint/spine_5_joint/spine_6_joint/spine_7_joint/right_shoulder_1_joint/right_arm_joint/right_forearm_joint"
let rightHandName = "root/hips_joint/spine_1_joint/spine_2_joint/spine_3_joint/spine_4_joint/spine_5_joint/spine_6_joint/spine_7_joint/right_shoulder_1_joint/right_arm_joint/right_forearm_joint/right_hand_joint"
let headName = "root/hips_joint/spine_1_joint/spine_2_joint/spine_3_joint/spine_4_joint/spine_5_joint/spine_6_joint/spine_7_joint/neck_1_joint/neck_2_joint/neck_3_joint/neck_4_joint/head_joint"

// MARK: - Animation Rotations
let identityRotation = simd_quatf() // NOTE: This is only used for the head nod reset now.
// MARK: - Animation Poses
// NOTE: The `restPose` is now dynamically created at runtime. This constant is used as a template.
let restPose = Pose(transforms: [:])


// MARK: - Animation Keyframes
var animationKeyframes: [Keyframe] = [
    Keyframe(time: 2.5, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: .pi/4, axis: [-3, -3, -4])),
        leftShoulderName: Transform(rotation: simd_quatf(angle: -.pi/4, axis: [-3, -3, -4])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/2.5, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [1, 0, 0]))
    ])),
    
    
    Keyframe(time: 3, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: .pi/4, axis: [-3, -3, -4])),
//        leftShoulderName: Transform(rotation: simd_quatf(angle: 0.5, axis: [0,-1,0])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [1, -0.3, 0.3]))
    ])),
    
    
    Keyframe(time: 4, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: .pi/4, axis: [-3, -3, -4])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/3, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [1, 0.6, 0.3]))
    ])),
    
    
    Keyframe(time: 5, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: .pi/4, axis: [-3, -3, -4])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [1, -0.3, 0.3]))
    ])),
    
    Keyframe(time: 6, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: .pi/4, axis: [-3, -3, -4])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/3, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [1, 0.6, 0.3]))
    ])),
    Keyframe(time: 7, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: .pi/4, axis: [-3, -3, -4])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [1, 0, 0]))
    ])),
    Keyframe(time: 8, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.5, axis: [0.01,-1,0.03])),
        rightArmName: Transform(rotation: simd_quatf(angle: 0, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 0, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: 1.571, axis: [-1, 0, 0]))
    ])),
    Keyframe(time: 9, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.5, axis: [0.01,-1,0.53])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/2, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: 1.571, axis: [-1, 0, 0]))
    ])),
    
    Keyframe(time: 9.5, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.5, axis: [0.01,-1,-0.23])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/2.5, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: 1.571, axis: [-1, -0.03, 0]))
    ])),
    
    Keyframe(time: 9.7, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.5, axis: [0.01,-1,-0.13])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/1.9, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: 1.571, axis: [-1, -0.03, 0]))
    ])),
    
    Keyframe(time: 9.9, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.5, axis: [0.01,-1,-0.23])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/2.5, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: 1.571, axis: [-1, -0.03, 0]))
    ])),
    
    
    Keyframe(time: 10.2, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.5, axis: [0.01,-1,-0.13])),
        rightArmName: Transform(rotation: simd_quatf(angle: .pi/8, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: -.pi/1.9, axis: [0,0,1])),
        rightHandName: Transform(rotation: simd_quatf(angle: 1.571, axis: [-1, -0.03, 0]))
    ])),
    Keyframe(time: 12, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 1.312, axis: [0.01,-1,0.03])),
        rightArmName: Transform(rotation: simd_quatf(angle: 0.261, axis: [0,-1,-0.06])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 0.084, axis: [0,0,-1])),
        rightHandName: Transform(rotation: simd_quatf(angle: 1.571, axis: [-1, 0, 0]))
    ])),
]
