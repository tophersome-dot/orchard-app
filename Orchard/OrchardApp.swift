import SwiftData
import SwiftUI

@main
struct OrchardApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
        }
        .modelContainer(OrchardStore.container)
    }
}

enum OrchardStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: Variety.self,
                Tasting.self,
                HuntItem.self,
                FarmPlacement.self,
                FarmDecor.self,
                FarmWorld.self,
                FarmStoredItem.self,
                FarmSkippedPlant.self
            )
        } catch {
            fatalError("Could not open the Orchard store: \(error)")
        }
    }()
}
