import SwiftData
import SwiftUI

struct FarmScreen: View {
    @Query(sort: \Variety.name) private var varieties: [Variety]
    @ObservedObject private var router = AppRouter.shared
    @State private var selected: VarietyLink?

    private var planted: [Variety] {
        varieties
            .filter(\.isTried)
            .sorted { ($0.firstTastedAt ?? .distantFuture) < ($1.firstTastedAt ?? .distantFuture) }
    }

    private var layout: PlotLayout {
        PlotLayout.make(
            orchard: slugs(in: .orchard),
            beds: slugs(in: .bed),
            trellis: slugs(in: .trellis),
            lab: slugs(in: .greenhouse)
        )
    }

    private var tastedCount: Int {
        Set(planted.map(\.slug)).count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    plot
                }
                .scrollIndicators(.hidden)
                .background(OrchardColor.grass)
                .onAppear { reveal(proxy, slug: router.focusSlug, initial: true) }
                .onChange(of: router.focusSlug) { _, slug in
                    reveal(proxy, slug: slug, initial: false)
                }
            }
        }
        .sheet(item: $selected) { link in
            VarietyDetailView(slug: link.id)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Chris's Orchard")
                    .font(OrchardFont.display(26))
                Text("\(tastedCount) planted")
                    .font(OrchardFont.body(14))
            }
            Spacer()
            ZStack {
                Circle().fill(OrchardColor.barn)
                Image(systemName: "apple.logo")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
        }
        .foregroundStyle(OrchardColor.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(OrchardColor.grass)
    }

    private var plot: some View {
        ZStack {
            FarmGround(layout: layout)
            FarmhouseArt(tier: HouseRules.progress(for: tastedCount).tier)
                .position(layout.house)
                .id("farmhouse")
            HouseSign(progress: HouseRules.progress(for: tastedCount))
                .position(layout.sign)
            TractorArt()
                .position(layout.tractor)
            GreenhouseArt()
                .position(layout.greenhouse)
            ForEach(planted) { variety in
                if let point = layout.slots[variety.slug] {
                    Button {
                        selected = VarietyLink(id: variety.slug)
                    } label: {
                        PlantMarker(
                            variety: variety,
                            health: PlantHealth.from(rating: variety.latestTasting?.overall ?? 3)
                        )
                    }
                    .buttonStyle(.plain)
                    .position(point)
                    .id(variety.slug)
                    .accessibilityLabel(accessLabel(variety))
                }
            }
            if planted.isEmpty {
                Text("Taste a variety and it will grow here.")
                    .font(OrchardFont.body(14))
                    .foregroundStyle(OrchardColor.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(OrchardColor.cream, in: Capsule())
                    .overlay(Capsule().stroke(OrchardColor.grassDeep, lineWidth: 2))
                    .position(x: layout.house.x, y: layout.house.y + 150)
            }
        }
        .frame(width: layout.canvas.width, height: layout.canvas.height)
    }

    private func slugs(in zone: FarmZone) -> [String] {
        planted.filter { $0.zone == zone }.map(\.slug)
    }

    private func accessLabel(_ variety: Variety) -> String {
        let health = PlantHealth.from(rating: variety.latestTasting?.overall ?? 3)
        let score = variety.latestTasting?.overall ?? 0
        return "\(variety.name), \(health.badge.label), \(String(format: "%.1f", score))"
    }

    private func reveal(_ proxy: ScrollViewProxy, slug: String?, initial: Bool) {
        let target = slug ?? (initial ? "farmhouse" : nil)
        guard let target else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(target, anchor: .center)
            }
            if slug != nil {
                router.focusSlug = nil
            }
        }
    }
}

struct VarietyLink: Identifiable, Hashable {
    var id: String
}
