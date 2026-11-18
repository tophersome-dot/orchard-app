import SwiftData
import SwiftUI

struct CollectionScreen: View {
    @Query(sort: \Variety.name) private var varieties: [Variety]
    @State private var category = "apple"
    @State private var showingHunt = false
    @State private var selected: VarietyLink?

    private var categories: [String] {
        let order = ProduceCategory.allCases.map(\.rawValue)
        let present = Set(varieties.map(\.categoryRaw))
        let known = order.filter { present.contains($0) }
        let extra = present.subtracting(order).sorted()
        return known + extra
    }

    private var inCategory: [Variety] {
        varieties.filter { $0.categoryRaw == category }
    }

    private var triedCount: Int {
        inCategory.filter(\.isTried).count
    }

    private var huntVarieties: [Variety] {
        varieties.filter(\.onHunt).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Collection")
                .font(OrchardFont.display(32))
                .foregroundStyle(OrchardColor.ink)
            Picker("View", selection: $showingHunt) {
                Text("Log").tag(false)
                Text("Hunt").tag(true)
            }
            .pickerStyle(.segmented)
            if showingHunt {
                huntBody
            } else {
                logBody
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OrchardColor.mint)
        .onAppear {
            if !categories.contains(category), let first = categories.first {
                category = first
            }
        }
        .sheet(item: $selected) { link in
            VarietyDetailView(slug: link.id)
        }
    }

    private var logBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { raw in
                        Button {
                            category = raw
                        } label: {
                            Text(ProduceCategory.title(for: raw))
                                .font(OrchardFont.body(14))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .foregroundStyle(OrchardColor.ink)
                                .background(category == raw ? OrchardColor.grass : OrchardColor.cream, in: Capsule())
                                .overlay(Capsule().stroke(OrchardColor.grassDeep, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("\(ProduceCategory.title(for: category)) \(triedCount) / \(inCategory.count)")
                .font(OrchardFont.display(22))
                .foregroundStyle(OrchardColor.ink)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                    ForEach(inCategory) { variety in
                        Button {
                            selected = VarietyLink(id: variety.slug)
                        } label: {
                            tile(variety)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 12)
            }
        }
    }

    private var huntBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shopping hunt \(huntVarieties.count)")
                .font(OrchardFont.display(22))
                .foregroundStyle(OrchardColor.ink)
            if huntVarieties.isEmpty {
                Text("No chase varieties yet. Open a card and add it to the shopping hunt.")
                    .font(OrchardFont.body(15))
                    .foregroundStyle(OrchardColor.ink.opacity(0.7))
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(huntVarieties) { variety in
                            Button {
                                selected = VarietyLink(id: variety.slug)
                            } label: {
                                HStack(spacing: 10) {
                                    FruitGlyph(id: variety.slug, form: variety.form, skin: variety.fruitSkin)
                                        .frame(width: 42, height: 42)
                                    VStack(alignment: .leading) {
                                        Text(variety.name)
                                            .font(OrchardFont.title(16))
                                        Text(ProduceCategory.title(for: variety.categoryRaw))
                                            .font(OrchardFont.caption(12))
                                            .foregroundStyle(OrchardColor.ink.opacity(0.55))
                                    }
                                    Spacer()
                                    Text("Chase")
                                        .font(OrchardFont.caption(12))
                                }
                                .foregroundStyle(OrchardColor.ink)
                                .padding(10)
                                .orchardCard()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func tile(_ variety: Variety) -> some View {
        let tried = variety.isTried
        return VStack(spacing: 4) {
            FruitGlyph(id: variety.slug, form: variety.form, skin: variety.fruitSkin)
                .frame(width: 64, height: 64)
                .saturation(tried ? 1 : 0)
                .opacity(tried ? 1 : 0.45)
            Text(variety.name)
                .font(OrchardFont.caption(11))
                .foregroundStyle(OrchardColor.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
            if let score = variety.latestTasting?.overall {
                Text(String(format: "%.1f", score))
                    .font(OrchardFont.title(12))
                    .foregroundStyle(OrchardColor.score(score))
            } else {
                Text("Chase")
                    .font(OrchardFont.caption(11))
                    .foregroundStyle(OrchardColor.ink.opacity(0.45))
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(OrchardColor.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(tried ? OrchardColor.grassDeep : OrchardColor.grassDeep.opacity(0.35), lineWidth: 2)
        )
    }
}
