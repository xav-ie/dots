import Foundation

class ScreenLockObserver {

init() {
        let dnc = DistributedNotificationCenter.default()

        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.logEvent(message: "Screen Locked")
        }

        dnc.addObserver(forName: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.logEvent(message: "Screen Unlocked")
            self?.runSketchybarCommands()
        }

        signal(SIGINT) { _ in
            ScreenLockObserver.shared.stop()
        }

        print("ScreenLockObserver is running. Press Ctrl+C to stop.")

        RunLoop.main.run()
    }

    private func logEvent(message: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        print("[\(timestamp)] \(message)")
    }

    private func runSketchybarCommands() {
        do {
            // Important for bar items to exist before trying to reload
            sleep(1)

            try runCommand("/usr/bin/env", arguments: ["sketchybar", "--reload"])
            logEvent(message: "Sketchybar restarted")
        } catch {
            logEvent(message: "Error executing sketchybar commands: \(error)")
        }
    }

    private func runCommand(_ command: String, arguments: [String]) throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: command)
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()

        task.standardOutput = outputPipe
        task.standardError = errorPipe

        task.terminationHandler = { process in
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                self.logEvent(message: "Command output: \(output)")
            }

            if let errorOutput = String(data: errorData, encoding: .utf8), !errorOutput.isEmpty {
                self.logEvent(message: "Command error: \(errorOutput)")
            }

            if process.terminationStatus != 0 {
                self.logEvent(message: "Command failed with status \(process.terminationStatus)")
            }
        }

        try task.run()
    }


    func stop() {
        print("ScreenLockObserver stopped.")
        exit(0)
    }

    static let shared = ScreenLockObserver()
}

ScreenLockObserver.shared
