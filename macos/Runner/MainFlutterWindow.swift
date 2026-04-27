import Cocoa
import FlutterMacOS
import window_manager
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
    private var powerChannel: FlutterMethodChannel?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    override func awakeFromNib() {
        let flutterViewController = FlutterViewController()
        let windowFrame = self.frame
        self.contentViewController = flutterViewController
        self.setFrame(windowFrame, display: true)
        
        FlutterMethodChannel(
            name: "launch_at_startup", binaryMessenger: flutterViewController.engine.binaryMessenger
        )
        .setMethodCallHandler { (_ call: FlutterMethodCall, result: @escaping FlutterResult) in
            switch call.method {
            case "launchAtStartupIsEnabled":
                result(LaunchAtLogin.isEnabled)
            case "launchAtStartupSetEnabled":
                if let arguments = call.arguments as? [String: Any] {
                    LaunchAtLogin.isEnabled = arguments["setEnabledValue"] as! Bool
                }
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        
        setupPowerChannel(binaryMessenger: flutterViewController.engine.binaryMessenger)
        RegisterGeneratedPlugins(registry: flutterViewController)
        super.awakeFromNib()
    }

    private func setupPowerChannel(binaryMessenger: FlutterBinaryMessenger) {
        powerChannel = FlutterMethodChannel(
            name: "com.follow.clash/power",
            binaryMessenger: binaryMessenger
        )
        let notificationCenter = NSWorkspace.shared.notificationCenter
        sleepObserver = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.powerChannel?.invokeMethod("willSleep", arguments: nil)
        }
        wakeObserver = notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.powerChannel?.invokeMethod("didWake", arguments: nil)
        }
    }

    deinit {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        if let sleepObserver = sleepObserver {
            notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver = wakeObserver {
            notificationCenter.removeObserver(wakeObserver)
        }
    }

    override public func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        hiddenWindowAtLaunch()
    }
}
