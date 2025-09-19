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
                let model = try await ModelEntity(named: "lowpoly")
                model.position = [0, 1.2, -2] // Adjusted Y for better viewing
            
                model.scale = [0.01,0.01,0.01]
                
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
        
        // Print all available joint names
        print("=== ALL JOINT NAMES ===")
        for (index, jointName) in model.jointNames.enumerated() {
            print("\(index): \(jointName)")
        }
        print("========================")
        
        var startingPoseTransforms: [String: Transform] = [:]
        var jointIndices: [String: Int] = [:]
        let requiredJoints = [
            rightShoulderName, leftShoulderName, rightArmName, rightForearmName, rightHandName,
            // All finger joints
            rightMiddle1Name, rightMiddle2Name,
            rightRing1Name, rightRing2Name,
            rightPinky1Name, rightPinky2Name,
            rightIndex1Name, rightIndex2Name,
            rightThumb1Name, rightThumb2Name
        ]

        for jointName in requiredJoints {
            if let index = model.jointNames.firstIndex(of: jointName) {
                jointIndices[jointName] = index
                // Read the actual transform from the model's default pose
                startingPoseTransforms[jointName] = model.jointTransforms[index]
            }
        }

        // Dynamically set the first keyframe to the model's actual starting pose.
        if !animationKeyframes.isEmpty {
            animationKeyframes[0].pose = Pose(transforms: startingPoseTransforms)
        }
        
        
        var animationTime: TimeInterval = 0
        
        self.subscription = scene.subscribe(to: SceneEvents.Update.self) { event in
            animationTime += event.deltaTime
            let loopedTime = animationTime.truncatingRemainder(dividingBy: 15)
            
            guard let (prevKeyframe, nextKeyframe) = findKeyframes(for: loopedTime) else { return }
            
            let timeInRange = loopedTime - prevKeyframe.time
            let rangeDuration = nextKeyframe.time - prevKeyframe.time
            // Prevent division by zero if keyframes have the same time
            let linearT = rangeDuration > 0 ? Float(timeInRange / rangeDuration) : 0
            let easedT = easeInOutBack(linearT)
            
            for (jointName, jointIndex) in jointIndices {
                // Ensure that both keyframes have a transform for the current joint.
                // If a transform is missing, the joint will hold its previous state for that segment.
                guard let prevTransform = prevKeyframe.pose.transforms[jointName],
                      let nextTransform = nextKeyframe.pose.transforms[jointName] else { continue }
                
                // Interpolate ONLY the rotation.
                let interpolatedRotation = simd_slerp(prevTransform.rotation, nextTransform.rotation, easedT)
                
                // Start with the model's current transform to preserve its position and scale.
                var newTransform = model.jointTransforms[jointIndex]
                newTransform.rotation = interpolatedRotation
                
                model.jointTransforms[jointIndex] = newTransform
            }
            
        } as! AnyCancellable
        
        animationPlaying = true
        print("Animation started successfully!")
    }

    private func findKeyframes(for time: TimeInterval) -> (Keyframe, Keyframe)? {
        // Find the two keyframes to interpolate between for a given time.
        
        if time < animationKeyframes.first?.time ?? 0 {
            // If before the first keyframe, hold the first keyframe's pose.
            return (animationKeyframes.first!, animationKeyframes.first!)
        }
        
        for i in 0..<(animationKeyframes.count - 1) {
            let current = animationKeyframes[i]
            let next = animationKeyframes[i + 1]
            if time >= current.time && time <= next.time {
                return (current, next)
            }
        }
        
        // If past the last keyframe, hold the last keyframe's pose.
        return (animationKeyframes.last!, animationKeyframes.last!)
    }
}

// MARK: - Joint Names (Updated for lowpoly model)
let rightShoulderName = "n9/n10/n14"
let leftShoulderName = "n9/n10/n33"
let rightArmName = "n9/n10/n14/n15"
let rightForearmName = "n9/n10/n14/n15/n16"
let rightHandName = "n9/n10/n14/n15/n16/n17"
let headName = "n52"

// All finger joints
let rightMiddle1Name = "n9/n10/n14/n15/n16/n17/n18"
let rightMiddle2Name = "n9/n10/n14/n15/n16/n17/n18/n19"
let rightRing1Name = "n9/n10/n14/n15/n16/n17/n21"
let rightRing2Name = "n9/n10/n14/n15/n16/n17/n21/n22"
let rightPinky1Name = "n9/n10/n14/n15/n16/n17/n24"
let rightPinky2Name = "n9/n10/n14/n15/n16/n17/n24/n25"
let rightIndex1Name = "n9/n10/n14/n15/n16/n17/n27"
let rightIndex2Name = "n9/n10/n14/n15/n16/n17/n27/n28"
let rightThumb1Name = "n9/n10/n14/n15/n16/n17/n30"
let rightThumb2Name = "n9/n10/n14/n15/n16/n17/n30/n31"

// MARK: - Animation Poses
// NOTE: The first keyframe is now dynamically created at runtime to match the model's default pose.
let restPose = Pose(transforms: [:])

// MARK: - Animation Keyframes
var animationKeyframes: [Keyframe] = [
    
    // Keyframe 1: Start Time / Rest Pose. This is dynamically populated at runtime.
    Keyframe(time: 0.5, pose: restPose),
        
    
    // Keyframe 2: Closed Fist
    Keyframe(time: 2, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.8, axis: [0, 0, -1])),
        rightArmName: Transform(rotation: simd_quatf(angle: -1.2, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 1.1, axis: [1,0,0])),
        // --- Fingers ---
        rightMiddle1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightMiddle2Name: Transform(rotation: simd_quatf(angle: 2, axis: [0,0,-1])),
        rightRing1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightRing2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightPinky1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightPinky2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightIndex1Name: Transform(rotation: simd_quatf(angle: 1.2, axis: [0,0,-1])),
        rightIndex2Name: Transform(rotation: simd_quatf(angle: 2, axis: [0,0,-1])),
        rightThumb1Name: Transform(rotation: simd_quatf(angle: 1.2, axis: [0,0,-1])),
        rightThumb2Name: Transform(rotation: simd_quatf(angle: 1, axis: [-1,0,0])),
    ])),
//        
    // Keyframe 3: Point with Index Finger
    Keyframe(time: 3, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.8, axis: [0, 0, -1])),
        rightArmName: Transform(rotation: simd_quatf(angle: -1.3, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 1.3, axis: [1,0,0])),

        // --- Fingers ---
        rightMiddle1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightMiddle2Name: Transform(rotation: simd_quatf(angle: 2, axis: [0,0,-1])),
        rightRing1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightRing2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightPinky1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightPinky2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightIndex1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightIndex2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightThumb1Name: Transform(rotation: simd_quatf(angle: 1, axis: [0,0,-1])),
        rightThumb2Name: Transform(rotation: simd_quatf(angle: 0.7, axis: [-1,0,0])),
    ])),
        
    // Keyframe 4: Peace Sign (Index and Middle finger up)
    Keyframe(time: 4, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.8, axis: [0, 0, -1])),
        rightArmName: Transform(rotation: simd_quatf(angle: -1.2, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 1.1, axis: [1,0,0])),
        // --- Fingers ---
        rightMiddle1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightMiddle2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightRing1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightRing2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightPinky1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightPinky2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightIndex1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightIndex2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightThumb1Name: Transform(rotation: simd_quatf(angle: 1, axis: [0,0,-1])),
        rightThumb2Name: Transform(rotation: simd_quatf(angle: 0.7, axis: [-1,0,0])),
    ])),
        
    // Keyframe 5: Rock and Roll Sign (Index and Pinky up)
    Keyframe(time: 5, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.8, axis: [0, 0, -1])),
        rightArmName: Transform(rotation: simd_quatf(angle: -1.3, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 1.3, axis: [1,0,0])),
        // --- Fingers ---
        rightMiddle1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightMiddle2Name: Transform(rotation: simd_quatf(angle: 2, axis: [0,0,-1])),
        rightRing1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightRing2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightPinky1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightPinky2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightIndex1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightIndex2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightThumb1Name: Transform(rotation: simd_quatf(angle: 1.2, axis: [0,0,-1])),
        rightThumb2Name: Transform(rotation: simd_quatf(angle: 0.7, axis: [-1,0,0])),
    ])),
        
    // Keyframe 6: Thumbs Up
    Keyframe(time: 6, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.8, axis: [0, 0, -1])),
        rightArmName: Transform(rotation: simd_quatf(angle: -1.2, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 1.1, axis: [1,0,0])),
        // --- Fingers ---
        rightMiddle1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightMiddle2Name: Transform(rotation: simd_quatf(angle: 2, axis: [0,0,-1])),
        rightRing1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightRing2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightPinky1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightPinky2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightIndex1Name: Transform(rotation: simd_quatf(angle: 1.2, axis: [0,0,-1])),
        rightIndex2Name: Transform(rotation: simd_quatf(angle: 2, axis: [0,0,-1])),
        rightThumb1Name: Transform(rotation: simd_quatf(angle: 0.5, axis: [1,0,0])),
        rightThumb2Name: Transform(rotation: simd_quatf(angle: -0.5, axis: [-1,0,0])),
    ])),
    
        
    // Keyframe 8: Wave Motion 2 (Hand open again)
    Keyframe(time: 8, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.8, axis: [0, 0, -1])),
        rightArmName: Transform(rotation: simd_quatf(angle: -1.2, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 1.1, axis: [1,0,0])),
        // --- Fingers ---
        rightMiddle1Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightMiddle2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightRing1Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightRing2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightPinky1Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightPinky2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightIndex1Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightIndex2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightThumb1Name: Transform(rotation: simd_quatf(angle: 0.2, axis: [0,0,-1])),
        rightThumb2Name: Transform(rotation: simd_quatf(angle: 0.2, axis: [-1,0,0])),
    ])),
        

        
    // Keyframe 12: Finger Guns
    Keyframe(time: 12, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.8, axis: [0, 0, -1])),
        rightArmName: Transform(rotation: simd_quatf(angle: -1.2, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 1.1, axis: [1,0,0])),
        // --- Fingers ---
        rightMiddle1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightMiddle2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightRing1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightRing2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightPinky1Name: Transform(rotation: simd_quatf(angle: 1.4, axis: [0,0,-1])),
        rightPinky2Name: Transform(rotation: simd_quatf(angle: 2.0, axis: [0,0,-1])),
        rightIndex1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])), // Point straight
        rightIndex2Name: Transform(rotation: simd_quatf(angle: -0.1, axis: [1,0,0])),
        rightThumb1Name: Transform(rotation: simd_quatf(angle: 0.6, axis: [1,0,0])), // Thumb up
        rightThumb2Name: Transform(rotation: simd_quatf(angle: -0.5, axis: [-1,0,0])),
    ])),
        
    // Keyframe 13: Open hand, preparing for final wave
    Keyframe(time: 12.6, pose: Pose(transforms: [
        rightShoulderName: Transform(rotation: simd_quatf(angle: 0.8, axis: [0, 0, -1])),
        rightArmName: Transform(rotation: simd_quatf(angle: -1.3, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 1.3, axis: [1,0,0])),
        rightHandName: Transform(rotation: simd_quatf(angle: 2.4, axis: [0.5,-1,0])),
        // --- Fingers ---
        rightMiddle1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightMiddle2Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightRing1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightRing2Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightPinky1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightPinky2Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightIndex1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightIndex2Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightThumb1Name: Transform(rotation: simd_quatf(angle: 0.3, axis: [1,0,0])),
        rightThumb2Name: Transform(rotation: simd_quatf(angle: -0.2, axis: [-1,0,0])),
    ])),
    
//        
    // Keyframe 14: Final pose to transition smoothly back to the start
    Keyframe(time: 14.5, pose: Pose(transforms: [
        // Return arm to a near-neutral position to blend with the start pose
        rightShoulderName: Transform(rotation: simd_quatf(angle: 1.5, axis: [0, 0, -1])),
        rightArmName: Transform(rotation: simd_quatf(angle: -0.1, axis: [0,1,0])),
        rightForearmName: Transform(rotation: simd_quatf(angle: 0.1, axis: [1,0,0])),
        rightHandName: Transform(rotation: simd_quatf(angle: 0, axis: [0,1,0])),
        // --- Fingers (open and relaxed) ---
        rightMiddle1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightMiddle2Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightRing1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightRing2Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightPinky1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightPinky2Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightIndex1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightIndex2Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightThumb1Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [1,0,0])),
        rightThumb2Name: Transform(rotation: simd_quatf(angle: 0.0, axis: [-1,0,0])),
    ]))
    
]
