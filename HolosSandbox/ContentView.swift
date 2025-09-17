import SwiftUI
import RealityKit

struct ContentView: View {
    // State variables to control the immersive space
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
    @State private var isImmersiveSpaceShown = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Robot Control")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Tap the button below to place the robot in your space and control its arm.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // A toggle to launch or close the immersive scene
            Toggle(isImmersiveSpaceShown ? "Exit Immersive Space" : "Enter Immersive Space", isOn: $isImmersiveSpaceShown)
                .toggleStyle(.button)
                .font(.headline)
        }
        .padding(30)
        .glassBackgroundEffect()
        .onChange(of: isImmersiveSpaceShown) { _, newValue in
            Task {
                if newValue {
                    // Open the immersive space with the specified ID.
                    await openImmersiveSpace(id: "ImmersiveRobotSpace")
                } else {
                    // Close the immersive space.
                    await dismissImmersiveSpace()
                }
            }
        }
    }
}
