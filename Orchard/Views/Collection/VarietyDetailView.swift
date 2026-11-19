import SwiftData
import SwiftUI
import UIKit

struct VarietyLink: Identifiable, Hashable {
    var id: String
}

struct VarietyDetailView: View {
    var slug: String
    @Query(sort: \Variety.name) private var varieties: [Variety]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @ObservedObject private var router = AppRouter.shared

    private var variety: Variety? {
        varieties.first { $0.slug == slug }
    }

    private var tastings: [Tasting] {
        (variety?.tastingList ?? []).sorted { $0.tastedAt > $1.tastedAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let variety {
                    VStack(alignment: .leading, spacing: 14) {
                        header(variety)
                        if let latest = variety.latestTasting {
                            ratingBlock(latest, count: tastings.count)
                        } else {
                            Text("Not tried yet")
                                .font(OrchardFont.title(16))
                                .foregroundStyle(OrchardColor.mid)
                        }
                        huntButton(variety)
                        if variety.recordKind == .marketType {
                            caption("A shop type, not one cultivar.")
                        }
                        infoBlock(title: "Where to find", text: variety.whereToFind, empty: "Not recorded")
                        infoBlock(
                            title: "Grown in",
                            text: variety.regions.joined(separator: ", "),
                            empty: "Growing regions not recorded"
                        )
                        seasonBlock(variety)
                        factBlock(variety)
                        if !variety.skinVerified {
                            caption("Colour sketch, not confirmed.")
                        }
                        if !tastings.isEmpty {
                            Text("Tastings")
                                .font(OrchardFont.title(18))
                            ForEach(tastings) { tasting in
                                tastingRow(tasting)
                            }
                        }
                        Button {
                            router.draftSlug = variety.slug
                            dismiss()
                            router.tab = .taste
                        } label: {
                            Text(tastings.isEmpty ? "Log a taste" : "Log another taste")
                                .font(OrchardFont.title(16))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .foregroundStyle(.white)
                                .background(OrchardColor.grassDeep, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        if variety.isCustom {
                            Button(role: .destructive) {
                                context.delete(variety)
                                try? context.save()
                                dismiss()
                            } label: {
                                Text("Remove custom variety")
                                    .font(OrchardFont.body(15))
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(16)
                } else {
                    Text("That variety isn't in the catalogue.")
                        .padding()
                }
            }
            .background(OrchardColor.mint)
            .navigationTitle(variety?.name ?? "Variety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func header(_ variety: Variety) -> some View {
        HStack(alignment: .center, spacing: 14) {
            FruitGlyph(id: variety.slug, form: variety.form, skin: variety.fruitSkin)
                .frame(width: 96, height: 96)
                .padding(8)
                .background(OrchardColor.cream, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(OrchardColor.grassDeep, lineWidth: 3))
            VStack(alignment: .leading, spacing: 4) {
                Text(variety.name)
                    .font(OrchardFont.display(26))
                    .foregroundStyle(OrchardColor.ink)
                Text(ProduceCategory.title(for: variety.categoryRaw))
                    .font(OrchardFont.body(14))
                    .foregroundStyle(OrchardColor.grassDeep)
                if !variety.aliases.isEmpty {
                    Text("Also called \(variety.aliases.joined(separator: ", "))")
                        .font(OrchardFont.caption(13))
                        .foregroundStyle(OrchardColor.ink.opacity(0.7))
                }
                if !variety.pluCodes.isEmpty {
                    Text("PLU \(variety.pluCodes.joined(separator: ", "))")
                        .font(OrchardFont.caption(12))
                        .foregroundStyle(OrchardColor.ink.opacity(0.55))
                }
            }
        }
    }

    private func ratingBlock(_ tasting: Tasting, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(format: "%.1f", tasting.scoreForDisplay))
                    .font(OrchardFont.display(36))
                    .foregroundStyle(OrchardColor.score(tasting.scoreForDisplay))
                Text(count == 1 ? "latest taste" : "latest of \(count)")
                    .font(OrchardFont.caption(13))
                    .foregroundStyle(OrchardColor.ink.opacity(0.6))
            }
            Text(TraitSummary.glance(
                notes: tasting.notes,
                sweet: tasting.sweet,
                tart: tasting.tart,
                crunch: tasting.crunch,
                juicy: tasting.juicy
            ))
            .font(OrchardFont.body(15))
            if !tasting.notes.isEmpty {
                Text(tasting.notes)
                    .font(OrchardFont.body(15))
                    .foregroundStyle(OrchardColor.ink)
            }
            if let data = tasting.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .orchardCard()
    }

    private func huntButton(_ variety: Variety) -> some View {
        Button {
            toggleHunt(variety)
        } label: {
            Label(
                variety.onHunt ? "On the shopping hunt" : "Add to shopping hunt",
                systemImage: variety.onHunt ? "basket.fill" : "basket"
            )
            .font(OrchardFont.title(16))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(variety.onHunt ? OrchardColor.ink : .white)
            .background(variety.onHunt ? OrchardColor.sun : OrchardColor.grassDeep, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func infoBlock(title: String, text: String, empty: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OrchardFont.title(14))
                .foregroundStyle(OrchardColor.grassDeep)
            Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? empty : text)
                .font(OrchardFont.body(15))
                .foregroundStyle(OrchardColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .orchardCard()
    }

    private func seasonBlock(_ variety: Variety) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(variety.seasonKind.heading)
                .font(OrchardFont.title(14))
                .foregroundStyle(OrchardColor.grassDeep)
            if variety.seasonMonths.isEmpty {
                Text(variety.seasonNote.isEmpty ? "Season not recorded" : variety.seasonNote)
                    .font(OrchardFont.body(15))
            } else {
                HStack(spacing: 4) {
                    ForEach(1...12, id: \.self) { month in
                        let on = variety.seasonMonths.contains(month)
                        Text(letter(month))
                            .font(OrchardFont.title(12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(on ? OrchardColor.grass : OrchardColor.mint, in: RoundedRectangle(cornerRadius: 4))
                            .foregroundStyle(on ? OrchardColor.ink : OrchardColor.ink.opacity(0.35))
                    }
                }
                if !variety.seasonNote.isEmpty {
                    Text(variety.seasonNote)
                        .font(OrchardFont.caption(12))
                        .foregroundStyle(OrchardColor.ink.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .orchardCard()
    }

    @ViewBuilder
    private func factBlock(_ variety: Variety) -> some View {
        if !variety.fact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Story")
                        .font(OrchardFont.title(14))
                        .foregroundStyle(OrchardColor.grassDeep)
                    if variety.factStatus == .unverified {
                        Text("Unverified")
                            .font(OrchardFont.caption(11))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OrchardColor.mid, in: Capsule())
                    }
                }
                Text(variety.fact)
                    .font(OrchardFont.body(15))
                    .foregroundStyle(OrchardColor.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .orchardCard()
        }
    }

    private func tastingRow(_ tasting: Tasting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(tasting.tastedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(OrchardFont.title(14))
                    Spacer()
                    Text(String(format: "%.1f", tasting.scoreForDisplay))
                        .font(OrchardFont.title(16))
                        .foregroundStyle(OrchardColor.score(tasting.scoreForDisplay))
                }
                if !tasting.notes.isEmpty {
                    Text(tasting.notes)
                        .font(OrchardFont.body(14))
                }
            }
            .foregroundStyle(OrchardColor.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .orchardCard()
            Button("Delete this tasting", role: .destructive) {
                context.delete(tasting)
                try? context.save()
            }
            .font(OrchardFont.caption(13))
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(OrchardFont.caption(13))
            .foregroundStyle(OrchardColor.ink.opacity(0.65))
    }

    private func letter(_ month: Int) -> String {
        let letters = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
        return letters[month - 1]
    }

    private func toggleHunt(_ variety: Variety) {
        if let existing = variety.huntList.first {
            context.delete(existing)
        } else {
            let item = HuntItem(id: UUID(), addedAt: Date())
            context.insert(item)
            item.variety = variety
        }
        try? context.save()
    }
}
