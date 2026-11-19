import AppIntents

struct OpenSupermarketIntent: AppIntent {
    static var title: LocalizedStringResource = "Supermarket mode"
    static var description = IntentDescription("Open Orchard ready to check a variety.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            AppRouter.shared.openShop()
        }
        return .result()
    }
}

struct OrchardShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenSupermarketIntent(),
            phrases: [
                "Open supermarket mode in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("Supermarket"),
            systemImage: "basket.fill"
        )
    }
}
