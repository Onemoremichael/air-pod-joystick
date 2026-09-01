import AppKit

@MainActor
final class PodStickAppDelegate: NSObject, NSApplicationDelegate {
    weak var motionController: MotionController?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        motionController?.shutdown()
    }
}
