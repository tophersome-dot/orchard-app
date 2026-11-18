import SwiftData
import SwiftUI

struct ShopScreen: View {
    @Query(sort: \Variety.name) private var varieties: [Variety]
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: (tried: [ShopHit], untried: [ShopHit]) {
        var latest: [String: TastingSnapshot] = [:]
        for variety in varieties {
            if let snapshot = variety.snapshot() {
                latest[variety.slug] = snapshot
            }
        }
        return CatalogueSearch.shopResults(
            query: query,
            varieties: varieties.map { $0.asEntry() },
            latestByVariety: latest
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Supermarket mode")
                .font(OrchardFont.display(32))
                .foregroundStyle(OrchardColor.ink)
            searchField
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if results.tried.isEmpty && results.untried.isEmpty {
                        Text(query.isEmpty ? "Nothing tasted yet. Log one and it will show up here." : "No varieties match.")
                            .font(OrchardFont.body(16))
                            .foregroundStyle(OrchardColor.ink.opacity(0.55))
                            .padding(.top, 24)
                    }
                    if !results.tried.isEmpty {
                        sectionTitle(query.isEmpty ? "Your ratings" : "Tasted")
                        ForEach(results.tried) { hit in
                            if let latest = hit.latest {
                                triedRow(hit.variety, latest: latest)
                            }
                        }
                    }
                    if !results.untried.isEmpty {
                        sectionTitle("Not tried yet")
                        ForEach(results.untried) { hit in
                            untriedRow(hit.variety)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
        .onAppear { focused = true }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(OrchardColor.grassDeep)
            TextField("Search variety, PLU or apple", text: $query)
                .font(OrchardFont.body(20))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(OrchardColor.ink.opacity(0.35))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(OrchardColor.grassDeep.opacity(0.35), lineWidth: 1)
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(OrchardFont.title(13))
            .foregroundStyle(OrchardColor.ink.opacity(0.45))
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func triedRow(_ variety: CatalogueEntry, latest: TastingSnapshot) -> some View {
        HStack(alignment: .center, spacing: 10) {
            shopFruit(variety.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(variety.name)
                    .font(OrchardFont.title(18))
                    .foregroundStyle(OrchardColor.ink)
                Text(TraitSummary.glance(
                    notes: latest.notes,
                    sweet: latest.sweet,
                    tart: latest.tart,
                    crunch: latest.crunch,
                    juicy: latest.juicy
                ))
                .font(OrchardFont.body(14))
                .foregroundStyle(OrchardColor.ink.opacity(0.55))
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(String(format: "%.1f", latest.overall))
                .font(OrchardFont.display(28))
                .foregroundStyle(OrchardColor.score(latest.overall))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OrchardColor.ink.opacity(0.08)).frame(height: 1)
        }
    }

    private func shopFruit(_ id: String) -> some View {
        Group {
            if let variety = varieties.first(where: { $0.slug == id }) {
                FruitGlyph(id: variety.slug, form: variety.form, skin: variety.fruitSkin)
            }
        }
        .frame(width: 40, height: 40)
    }

    private func untriedRow(_ variety: CatalogueEntry) -> some View {
        HStack {
            shopFruit(variety.id)
            VStack(alignment: .leading, spacing: 2) {
                Text(variety.name)
                    .font(OrchardFont.title(17))
                    .foregroundStyle(OrchardColor.ink.opacity(0.8))
                Text(ProduceCategory.title(for: variety.category))
                    .font(OrchardFont.caption(13))
                    .foregroundStyle(OrchardColor.ink.opacity(0.4))
            }
            Spacer()
            Text("Not tried yet")
                .font(OrchardFont.caption(13))
                .foregroundStyle(OrchardColor.ink.opacity(0.4))
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OrchardColor.ink.opacity(0.08)).frame(height: 1)
        }
    }
}
