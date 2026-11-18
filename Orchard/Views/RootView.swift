import SwiftData
import SwiftUI

struct RootView: View {
    @ObservedObject private var router = AppRouter.shared
    @State private var seedError: String?

    var body: some View {
        Group {
            switch router.tab {
            case .farm:
                FarmScreen()
            case .taste:
                TasteScreen()
            case .shop:
                ShopScreen()
            case .collection:
                CollectionScreen()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            OrchardTabBar(selection: Binding(get: { router.tab }, set: { router.tab = $0 }))
        }
        .task {
            // Let the empty farm (shed, tractor, plots) commit before any store work.
            await Task.yield()
            do {
                let importer = CatalogueImporter(modelContainer: OrchardStore.container)
                try await importer.importSeed(includeSamples: DebugLaunch.seedSampleTastings)
            } catch {
                seedError = error.localizedDescription
            }
        }
        .onAppear { router.consumeQuickAction() }
        .onReceive(NotificationCenter.default.publisher(for: QuickActionBridge.notification)) { _ in
            router.consumeQuickAction()
        }
        .overlay(alignment: .top) {
            if let seedError {
                Text(seedError)
                    .font(OrchardFont.caption(13))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(OrchardColor.bad, in: RoundedRectangle(cornerRadius: 10))
                    .padding()
            }
        }
    }
}

struct OrchardTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            item(.farm, title: "Farm", symbol: "house")
            item(.taste, title: "Taste", symbol: "fork.knife")
            item(.shop, title: "Shop", symbol: "basket")
            item(.collection, title: "Collection", symbol: "book")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
    }

    private func item(_ tab: AppTab, title: String, symbol: String) -> some View {
        let active = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .light))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(active ? OrchardColor.grassDeep : Color.black.opacity(0.42))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
