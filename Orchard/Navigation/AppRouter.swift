import Foundation
import UIKit

enum AppTab: String, Hashable {
    case farm
    case taste
    case shop
    case collection
}

@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()

    @Published var tab: AppTab
    @Published var focusSlug: String?
    @Published var draftSlug: String?

    private init() {
        tab = DebugLaunch.initialTab
    }

    func openShop() {
        tab = .shop
    }

    func showPlanted(_ slug: String) {
        focusSlug = slug
        tab = .farm
    }

    func consumeQuickAction() {
        if QuickActionBridge.shared.take() == QuickActionBridge.supermarket {
            tab = .shop
        }
    }
}

enum QuickActionBridge {
    static let supermarket = "com.chrismartin.orchard.supermarket"
    static let notification = Notification.Name("OrchardQuickAction")
    static let shared = Storage()

    final class Storage {
        private let lock = NSLock()
        private var pending: String?

        func store(_ type: String) {
            lock.lock()
            pending = type
            lock.unlock()
            NotificationCenter.default.post(name: QuickActionBridge.notification, object: type)
        }

        func take() -> String? {
            lock.lock()
            defer { lock.unlock() }
            let value = pending
            pending = nil
            return value
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.shortcutItems = [
            UIApplicationShortcutItem(
                type: QuickActionBridge.supermarket,
                localizedTitle: "Supermarket mode",
                localizedSubtitle: "Ratings while you shop",
                icon: UIApplicationShortcutIcon(systemImageName: "basket.fill"),
                userInfo: nil
            )
        ]
        if let item = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            QuickActionBridge.shared.store(item.type)
        }
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        QuickActionBridge.shared.store(shortcutItem.type)
        completionHandler(true)
    }
}
