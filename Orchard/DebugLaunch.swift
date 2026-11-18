import Foundation

enum DebugLaunch {
    static var seedSampleTastings: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-seedSampleTastings")
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
