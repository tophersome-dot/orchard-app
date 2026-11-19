import Foundation
import Observation

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
    static var showStorage: Bool { flag("-showStorage") }
    /// Opens edit mode with a plant selected.
    static var editSelection: Bool { flag("-editSelection") }
    /// Opens the axe with a tree frozen mid-fall.
    static var axeClear: Bool { flag("-axeClear") }
    /// Shows the first-run hint even if it was dismissed.
    static var showHints: Bool { flag("-showHints") }

    /// True when the process arguments or the argument-domain defaults include the flag.
    /// A valued flag later in the list must not hide this one.
    static func flag(_ name: String) -> Bool {
        #if DEBUG
        let dashed = name.hasPrefix("-") ? name : "-" + name
        let args = ProcessInfo.processInfo.arguments
        if args.contains(where: { $0.caseInsensitiveCompare(dashed) == .orderedSame }) { return true }
        if args.contains(where: { $0.lowercased().hasPrefix(dashed.lowercased() + "=") }) { return true }
        let key = String(dashed.dropFirst())
        if UserDefaults.standard.bool(forKey: key) { return true }
        if let text = UserDefaults.standard.string(forKey: key)?.lowercased(), text == "1" || text == "true" || text == "yes" {
            return true
        }
        return false
        #else
        return false
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

/// One copy of the launch flags, shared by every `FarmScreen`.
/// The ring, the toolbar and the camera read this. The logs print this same object.
@Observable
final class LaunchOverrides {
    static let shared = LaunchOverrides()

    private(set) var islandLevel: Int?
    private(set) var farmZoom: Double?
    private(set) var editSelection = false
    private(set) var showStorage = false
    private(set) var axeClear = false
    private(set) var showHints = false
    private(set) var demoTerrain = false
    private(set) var noWoods = false

    /// Level drawn in the ring and passed to the island generator.
    func resolvedLevel(tastedCount: Int) -> Int {
        if let islandLevel { return islandLevel }
        return max(1, tastedCount + 1)
    }

    /// Pulls the current process arguments. Safe to call more than once.
    func refresh() {
        let level = DebugLaunch.islandLevel
        let zoom = DebugLaunch.farmZoom.map { Double($0) }
        let edit = DebugLaunch.editSelection
        let storage = DebugLaunch.showStorage
        let axe = DebugLaunch.axeClear
        let hints = DebugLaunch.showHints
        let demo = DebugLaunch.demoTerrain
        let woods = DebugLaunch.noWoods
        guard level != islandLevel || zoom != farmZoom || edit != editSelection || storage != showStorage
                || axe != axeClear || hints != showHints || demo != demoTerrain || woods != noWoods else { return }
        islandLevel = level
        farmZoom = zoom
        editSelection = edit
        showStorage = storage
        axeClear = axe
        showHints = hints
        demoTerrain = demo
        noWoods = woods
        OrchardTiming.log("launch model level \(String(describing: level)) edit \(edit) storage \(storage) axe \(axe) zoom \(String(describing: zoom))")
    }
}
