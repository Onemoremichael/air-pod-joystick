import SwiftUI

@main
struct PodStickApp: App {
    @NSApplicationDelegateAdaptor(PodStickAppDelegate.self) private var appDelegate
    @StateObject private var motion = MotionController()

    var body: some Scene {
        WindowGroup("PodStick Motion Playground") {
            ContentView()
                .environmentObject(motion)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear {
                    appDelegate.motionController = motion
                    motion.start()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 920, height: 620)
    }
}
