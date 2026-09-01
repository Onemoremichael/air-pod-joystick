import SwiftUI

@main
struct PodStickApp: App {
    @StateObject private var motion = MotionController()

    var body: some Scene {
        WindowGroup("PodStick Motion Playground") {
            ContentView()
                .environmentObject(motion)
                .frame(minWidth: 820, minHeight: 560)
                .onAppear { motion.start() }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 920, height: 620)
    }
}
