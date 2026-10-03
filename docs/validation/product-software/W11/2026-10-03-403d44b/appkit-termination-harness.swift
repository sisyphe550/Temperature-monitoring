import AppKit
import Foundation

@MainActor
final class TerminationDelegate: NSObject, NSApplicationDelegate {
    let mode: String
    let start = ProcessInfo.processInfo.systemUptime
    init(mode: String) { self.mode = mode }
    func emit(_ event: String) {
        let value: [String: Any] = ["event": event, "mode": mode, "pid": ProcessInfo.processInfo.processIdentifier,
                                   "awake_seconds": ProcessInfo.processInfo.systemUptime - start,
                                   "main_thread": Thread.isMainThread]
        FileHandle.standardOutput.write(try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]))
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        emit("did_finish_launching")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000)
            emit("task_timer_completed")
            switch mode {
            case "task":
                emit("task_enter_terminate")
                NSApp.terminate(nil)
            case "main-async":
                DispatchQueue.main.async {
                    self.emit("main_async_enter_terminate")
                    NSApp.terminate(nil)
                }
            case "runloop":
                RunLoop.main.perform(inModes: [.common]) {
                    MainActor.assumeIsolated {
                        self.emit("runloop_enter_terminate")
                        NSApp.terminate(nil)
                    }
                }
            default:
                emit("invalid_mode")
                exit(2)
            }
            emit("initial_task_returned")
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        emit("should_terminate_return_later")
        Task { @MainActor in
            emit("reply_task_started")
            try? await Task.sleep(nanoseconds: 20_000_000)
            emit("reply_true")
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
    func applicationWillTerminate(_ notification: Notification) { emit("will_terminate") }
}

let mode = CommandLine.arguments.dropFirst().first ?? "task"
let delegate = TerminationDelegate(mode: mode)
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
application.delegate = delegate
application.run()
delegate.emit("application_run_returned")
