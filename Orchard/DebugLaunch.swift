import Foundation

enum DebugLaunch {
    static var demoTerrain: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-demoTerrain")
        #else
        false
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
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-farmZoom"), index + 1 < arguments.count else {
            return nil
        }
        guard let value = Double(arguments[index + 1]), value > 0 else { return nil }
        return CGFloat(value)
        #else
        return nil
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
