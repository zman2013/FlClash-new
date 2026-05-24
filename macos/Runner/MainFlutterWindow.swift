import Cocoa
import FlutterMacOS
import window_manager
import LaunchAtLogin

class MainFlutterWindow: NSWindow {
    private var appChannel: FlutterMethodChannel?
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
        
        let binaryMessenger = flutterViewController.engine.binaryMessenger
        setupAppChannel(binaryMessenger: binaryMessenger)
        setupPowerChannel(binaryMessenger: binaryMessenger)
        RegisterGeneratedPlugins(registry: flutterViewController)
        super.awakeFromNib()
    }

    private func setupAppChannel(binaryMessenger: FlutterBinaryMessenger) {
        appChannel = FlutterMethodChannel(
            name: "com.follow.clash/app",
            binaryMessenger: binaryMessenger
        )
        appChannel?.setMethodCallHandler { [weak self] call, result in
            guard let self = self else {
                result(FlutterError(code: "unavailable", message: "Window unavailable", details: nil))
                return
            }
            switch call.method {
            case "getPackages":
                result(self.getPackagesJSON())
            case "getPackageIcon":
                guard
                    let arguments = call.arguments as? [String: Any],
                    let packageName = arguments["packageName"] as? String
                else {
                    result(nil)
                    return
                }
                result(self.getPackageIconPath(packageName))
            case "getChinaPackageNames":
                result("[]")
            case "openFile":
                guard
                    let arguments = call.arguments as? [String: Any],
                    let path = arguments["path"] as? String
                else {
                    result(false)
                    return
                }
                result(NSWorkspace.shared.open(URL(fileURLWithPath: path)))
            case "moveTaskToBack", "requestNotificationsPermission", "tip",
                 "initShortcuts", "updateExcludeFromRecents":
                result(true)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private func getPackagesJSON() -> String {
        let packages = getApplicationURLs().compactMap { url -> [String: Any]? in
            guard let bundle = Bundle(url: url) else {
                return nil
            }
            let label = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?
                .timeIntervalSince1970 ?? 0
            return [
                "packageName": url.path,
                "label": label,
                "system": url.path.hasPrefix("/System/"),
                "internet": true,
                "lastUpdateTime": Int(modifiedAt * 1000),
            ]
        }
        let sortedPackages = packages.sorted {
            ($0["label"] as? String ?? "") < ($1["label"] as? String ?? "")
        }
        guard
            let data = try? JSONSerialization.data(withJSONObject: sortedPackages),
            let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }

    private func getApplicationURLs() -> [URL] {
        let homeApplications = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .path
        let roots = [
            "/Applications",
            "/Applications/Utilities",
            homeApplications,
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        var seen = Set<String>()
        var urls: [URL] = []
        for root in roots {
            guard
                let enumerator = FileManager.default.enumerator(
                    at: URL(fileURLWithPath: root),
                    includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
            else {
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "app" {
                if seen.insert(url.path).inserted {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private func getPackageIconPath(_ packageName: String) -> String? {
        guard let appPath = resolveApplicationPath(packageName) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appPath)
        icon.size = NSSize(width: 64, height: 64)
        guard
            let tiffData = icon.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return nil
        }
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flclash_app_icons", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let filename = "\(abs(packageName.hashValue)).png"
        let fileURL = directory.appendingPathComponent(filename)
        do {
            try pngData.write(to: fileURL)
            return fileURL.path
        } catch {
            return nil
        }
    }

    private func resolveApplicationPath(_ packageName: String) -> String? {
        if FileManager.default.fileExists(atPath: packageName) {
            return packageName
        }
        for url in getApplicationURLs() {
            let bundle = Bundle(url: url)
            let bundleIdentifier = bundle?.bundleIdentifier
            let executableName = bundle?.executableURL?.deletingPathExtension().lastPathComponent
            if bundleIdentifier == packageName ||
                executableName == packageName ||
                url.deletingPathExtension().lastPathComponent == packageName {
                return url.path
            }
        }
        return nil
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
