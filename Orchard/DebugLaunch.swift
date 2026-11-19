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

    /// Overrides the collection level that sizes the island. Example: `-islandLevel 1`
    static var islandLevel: Int? {
        #if DEBUG
        guard let raw = flagValue("islandLevel"), let value = Int(raw), value > 0 else { return nil }
        return value
        #else
        return nil
        #endif
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
            return args[index + 1]
        }
        let prefix = dashed + "="
        if let inline = args.first(where: { $0.hasPrefix(prefix) }) {
            return String(inline.dropFirst(prefix.count))
        }
        let key = String(dashed.dropFirst())
        if let text = UserDefaults.standard.string(forKey: key), !text.isEmpty {
            return text
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            let number = UserDefaults.standard.double(forKey: key)
            if number != 0 { return String(number) }
        }
        return nil
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
