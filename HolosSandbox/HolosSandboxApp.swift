import SwiftUI

@main
struct HolosSandboxApp: App {
    var body: some Scene {
        // This is the initial window the user sees when launching the app.
        // It will display the ContentView.
        WindowGroup {
            ContentView()
        }
        .windowStyle(.volumetric) // Optional: Makes the window a 3D volume.

        // This defines the immersive space that can be opened from the ContentView.
        // It uses ImmersiveView to display the 3D content.
        ImmersiveSpace(id: "ImmersiveRobotSpace") {
            ImmersiveView() 
        }
    }
}
