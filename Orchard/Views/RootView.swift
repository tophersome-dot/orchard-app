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
        HStack {
            item(.farm, title: "Farm", symbol: "tree.fill")
            item(.taste, title: "Taste", symbol: "apple.logo")
            item(.shop, title: "Shop", symbol: "basket.fill")
            item(.collection, title: "Collection", symbol: "book.fill")
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(OrchardColor.cream)
        .overlay(alignment: .top) {
            Rectangle().fill(OrchardColor.grassDeep).frame(height: 3)
        }
    }

    private func item(_ tab: AppTab, title: String, symbol: String) -> some View {
        Button {
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .bold))
                    .frame(width: 36, height: 28)
                    .background(selection == tab ? OrchardColor.grass : Color.clear, in: Capsule())
                Text(title)
                    .font(OrchardFont.caption(11))
            }
            .foregroundStyle(selection == tab ? OrchardColor.ink : OrchardColor.grassDeep.opacity(0.7))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}
