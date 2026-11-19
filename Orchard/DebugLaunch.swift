import Foundation

enum OrchardTiming {
    static let boot = CFAbsoluteTimeGetCurrent()

    static func log(_ message: String) {
        #if DEBUG
        print(String(format: "orchard.timing %.3fs %@", CFAbsoluteTimeGetCurrent() - boot, message))
        #endif
    }
}

enum DebugLaunch {
    static var demoTerrain: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demoTerrain")
        #else
        false
        #endif
    }

    /// Skip woodland decor and forest floor. The island, water, and cliffs still draw.
    static var noWoods: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-noWoods")
        #else
        false
        #endif
    }

    /// Overrides the collection level that sizes the island and the level ring. Example: `-islandLevel 1`
    static var islandLevel: Int? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        for (index, arg) in args.enumerated() {
            let token = arg.lowercased()
            if token == "-islandlevel" {
                if index + 1 < args.count, let value = positiveInt(args[index + 1]) {
                    return value
                }
                continue
            }
            if token.hasPrefix("-islandlevel=") {
                let raw = String(arg.dropFirst("-islandlevel=".count))
                if let value = positiveInt(raw) { return value }
            }
        }
        if let raw = flagValue("islandLevel"), let value = positiveInt(raw) {
            return value
        }
        return nil
        #else
        return nil
        #endif
    }

    /// `1` and `1.0` both count. A following flag such as `-seedSampleTastings` does not.
    static func positiveInt(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-") else { return nil }
        if let value = Int(trimmed), value > 0 { return value }
        if let value = Double(trimmed), value >= 1 { return Int(value) }
        return nil
    }

    static var seedSampleTastings: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-seedSampleTastings")
        #else
        false
        #endif
    }

    /// Absolute camera scale for the farm. `1` draws one tile width as `IsoMap.tileWidth` points.
    /// Example: `-farmZoom 0.45`
    static var farmZoom: CGFloat? {
        #if DEBUG
        guard let raw = flagValue("farmZoom"), let value = Double(raw), value > 0 else { return nil }
        return CGFloat(value)
        #else
        return nil
        #endif
    }

    /// `-name value` from argv, `-name=value`, or the matching UserDefaults entry.
    /// iOS copies launch arguments of that form into `UserDefaults` even when a host drops them from `arguments`.
    static func flagValue(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        let dashed = name.hasPrefix("-") ? name : "-" + name
        if let index = args.firstIndex(of: dashed), index + 1 < args.count {
            let next = args[index + 1]
            if !next.hasPrefix("-") { return next }
        }
        let prefix = dashed + "="
        if let inline = args.first(where: { $0.hasPrefix(prefix) }) {
            return String(inline.dropFirst(prefix.count))
        }
        let key = String(dashed.dropFirst())
        if let text = UserDefaults.standard.string(forKey: key), !text.isEmpty, !text.hasPrefix("-") {
            return text
        }
        if let number = UserDefaults.standard.object(forKey: key) as? NSNumber, number.doubleValue != 0 {
            if number.doubleValue == Double(number.intValue) { return String(number.intValue) }
            return number.stringValue
        }
        return nil
    }

    /// Opens edit mode with the storage tray visible.
    static var showStorage: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-showStorage")
        #else
        false
        #endif
    }

    /// Opens edit mode with a plant selected.
    static var editSelection: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-editSelection")
        #else
        false
        #endif
    }

    /// Opens the axe with a tree frozen mid-fall.
    static var axeClear: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-axeClear")
        #else
        false
        #endif
    }

    /// Shows the first-run hint bubbles even if they were dismissed.
    static var showHints: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-showHints")
        #else
        false
        #endif
    }

    static var initialTab: AppTab {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-openScreen"), index + 1 < arguments.count else {
            return .farm
        }
        switch arguments[index + 1].lowercased() {
        case "taste": return .taste
        case "shop", "supermarket": return .shop
        case "collection": return .collection
        default: return .farm
        }
        #else
        return .farm
        #endif
    }
}
