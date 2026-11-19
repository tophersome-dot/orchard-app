import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct TasteScreen: View {
    @Query(sort: \Variety.name) private var varieties: [Variety]
    @Environment(\.modelContext) private var context
    @ObservedObject private var router = AppRouter.shared

    @State private var selectedSlug: String?
    @State private var sweet = 3.0
    @State private var tart = 3.0
    @State private var crunch = 3.0
    @State private var juicy = 3.0
    @State private var overall = 3.0
    @State private var overallIsManual = false
    @State private var notes = ""
    @State private var image: UIImage?
    @State private var photoItem: PhotosPickerItem?
    @State private var showSources = false
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showPicker = false
    @State private var showCustom = false
    @State private var identifyMessage = "Snap the sticker or fruit, or pick a variety."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Quick taste")
                    .font(OrchardFont.display(32))
                    .foregroundStyle(OrchardColor.ink)
                photoCard
                Text(identifyMessage)
                    .font(OrchardFont.body(14))
                    .foregroundStyle(OrchardColor.ink)
                varietyButton
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your taste snapshot")
                        .font(OrchardFont.title(16))
                    TasteSlider(title: "Sweet", tint: Color(red: 0.95, green: 0.55, blue: 0.2), value: $sweet)
                    TasteSlider(title: "Tart", tint: OrchardColor.leaf, value: $tart)
                    TasteSlider(title: "Crunch", tint: OrchardColor.barn, value: $crunch)
                    TasteSlider(title: "Juicy", tint: Color(red: 0.2, green: 0.55, blue: 0.9), value: $juicy)
                }
                .orchardCard()
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Overall")
                            .font(OrchardFont.title(16))
                        if overallIsManual {
                            Button(action: resetOverall) {
                                Label("Reset", systemImage: "arrow.uturn.backward")
                                    .font(OrchardFont.caption(12))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Reset overall to the slider average")
                        } else {
                            Label("Auto", systemImage: "sparkles")
                                .font(OrchardFont.caption(12))
                                .foregroundStyle(OrchardColor.grassDeep)
                                .accessibilityLabel("Overall is the average of the sliders")
                        }
                    }
                    AppleScorePicker(score: $overall) {
                        overallIsManual = true
                    }
                }
                .orchardCard()
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: overall)
                VStack(alignment: .leading, spacing: 8) {
                    Label("Notes", systemImage: "pencil")
                        .font(OrchardFont.title(16))
                    TextField("Crunch, where you bought it…", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                        .font(OrchardFont.body(16))
                }
                .orchardCard()
                Button(action: plant) {
                    Label("Plant it", systemImage: "leaf.fill")
                        .font(OrchardFont.display(22))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(selectedSlug == nil ? OrchardColor.grassDeep.opacity(0.35) : OrchardColor.grassDeep, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedSlug == nil)
            }
            .padding(16)
        }
        .background(OrchardColor.mint)
        .scrollDismissesKeyboard(.interactively)
        .confirmationDialog("Add a photo", isPresented: $showSources, titleVisibility: .visible) {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take photo") { showCamera = true }
            }
            Button("Choose photo") { showLibrary = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { picture in
                image = picture
                Task { await identify(picture) }
            }
        }
        .sheet(isPresented: $showPicker) {
            VarietyPickerSheet(varieties: varieties, selectedSlug: $selectedSlug, showCustom: $showCustom)
        }
        .sheet(isPresented: $showCustom) {
            CustomVarietySheet { slug in
                selectedSlug = slug
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let picture = UIImage(data: data) {
                    image = picture
                    await identify(picture)
                }
            }
        }
        .onAppear(perform: applyDraft)
        .onChange(of: router.draftSlug) { _, _ in applyDraft() }
        .onChange(of: sliderSignature) { _, _ in syncOverall() }
    }

    private var photoCard: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [OrchardColor.soil, OrchardColor.woodDark], startPoint: .top, endPoint: .bottom)
                Image(systemName: "apple.logo")
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(OrchardColor.barn.opacity(0.85))
            }
            Button {
                showSources = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(OrchardColor.grassDeep)
                    .frame(width: 64, height: 64)
                    .background(.white, in: Circle())
                    .overlay(Circle().stroke(OrchardColor.grassDeep, lineWidth: 3))
            }
            .accessibilityLabel("Snap the sticker or fruit")
        }
        .frame(height: 210)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
    }

    private var varietyButton: some View {
        Button {
            showPicker = true
        } label: {
            HStack {
                Image(systemName: "apple.logo")
                    .foregroundStyle(OrchardColor.barn)
                Text(selectedName)
                    .font(OrchardFont.title(18))
                    .foregroundStyle(OrchardColor.ink)
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundStyle(OrchardColor.grassDeep)
            }
            .padding(14)
            .background(OrchardColor.cream, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var selectedName: String {
        guard let selectedSlug, let variety = varieties.first(where: { $0.slug == selectedSlug }) else {
            return "Choose a variety"
        }
        return "\(ProduceCategory(rawValue: variety.categoryRaw)?.singular ?? "Variety") · \(variety.name)"
    }

    private var automaticOverall: Double {
        TasteScore.automatic(sweet: sweet, tart: tart, crunch: crunch, juicy: juicy)
    }

    private var sliderSignature: String {
        "\(sweet)|\(tart)|\(crunch)|\(juicy)"
    }

    private func syncOverall() {
        guard !overallIsManual else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            overall = automaticOverall
        }
    }

    private func resetOverall() {
        overallIsManual = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            overall = automaticOverall
        }
    }

    private func applyDraft() {
        guard let slug = router.draftSlug else { return }
        selectedSlug = slug
        router.draftSlug = nil
    }

    private func identify(_ picture: UIImage) async {
        let text = await TextRecognizer.recognize(picture)
        let match = StickerMatch.suggest(text: text, varieties: varieties.map { $0.asEntry() })
        if let match, let name = varieties.first(where: { $0.slug == match.varietyID })?.name {
            selectedSlug = match.varietyID
            identifyMessage = "Looks like \(name). \(match.reason). Change it if that's wrong."
        } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            identifyMessage = "Couldn't read text on that photo. Pick the variety below."
        } else {
            identifyMessage = "Couldn't match that label. Pick the variety below."
        }
    }

    private func plant() {
        guard let selectedSlug, let variety = varieties.first(where: { $0.slug == selectedSlug }) else { return }
        let tasting = Tasting(
            id: UUID(),
            tastedAt: Date(),
            sweet: sweet,
            tart: tart,
            crunch: crunch,
            juicy: juicy,
            overall: overallIsManual ? overall : automaticOverall,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            photoData: image?.jpegData(compressionQuality: 0.8),
            overallIsOverride: overallIsManual
        )
        context.insert(tasting)
        tasting.variety = variety
        try? context.save()
        router.showPlanted(selectedSlug)
    }
}

private struct TasteSlider: View {
    var title: String
    var tint: Color
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(OrchardFont.body(14))
                .frame(width: 64, alignment: .leading)
            Slider(value: $value, in: 0...5, step: 0.5)
                .tint(tint)
            Text(String(format: "%.1f", value))
                .font(OrchardFont.caption(12))
                .frame(width: 28, alignment: .trailing)
        }
        .foregroundStyle(OrchardColor.ink)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(title) \(String(format: "%.1f", value)) of 5")
    }
}

private struct AppleScorePicker: View {
    @Binding var score: Double
    var onAdjust: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { index in
                apple(index: index)
            }
            Spacer(minLength: 4)
            Text(String(format: "%.1f of 5", score))
                .font(OrchardFont.title(16))
                .foregroundStyle(OrchardColor.score(score))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: score)
        }
    }

    private func apple(index: Int) -> some View {
        let amount = CGFloat(min(1, max(0, score - Double(index - 1))))
        return ZStack(alignment: .leading) {
            MiniApple().opacity(0.25)
            MiniApple()
                .mask(alignment: .leading) {
                    Rectangle().frame(width: 36 * amount)
                }
        }
        .frame(width: 36, height: 36)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: score)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onEnded { value in
                let half = value.location.x < 18
                let next = Double(index) - (half ? 0.5 : 0)
                score = min(5, max(1, next))
                onAdjust()
            }
        )
        .accessibilityLabel("Set overall to \(index)")
    }
}

private struct MiniApple: View {
    var body: some View {
        ZStack {
            Circle().fill(OrchardColor.barn)
            Circle().fill(Color.white.opacity(0.35)).frame(width: 8, height: 6).offset(x: -6, y: -6)
            Capsule().fill(OrchardColor.woodDark).frame(width: 3, height: 8).offset(y: -16)
            Ellipse().fill(OrchardColor.leaf).frame(width: 10, height: 6).rotationEffect(.degrees(-30)).offset(x: 7, y: -15)
        }
    }
}

struct VarietyPickerSheet: View {
    var varieties: [Variety]
    @Binding var selectedSlug: String?
    @Binding var showCustom: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Variety] {
        let compact = OrchardText.compact(query)
        guard !compact.isEmpty else { return varieties }
        return varieties.filter { variety in
            CatalogueSearch.matches(variety.asEntry(), query: query)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { variety in
                    Button {
                        selectedSlug = variety.slug
                        dismiss()
                    } label: {
                        HStack {
                            FruitGlyph(id: variety.slug, form: variety.form, skin: variety.fruitSkin)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading) {
                                Text(variety.name)
                                    .font(OrchardFont.title(16))
                                Text(ProduceCategory.title(for: variety.categoryRaw))
                                    .font(OrchardFont.caption(12))
                                    .foregroundStyle(OrchardColor.ink.opacity(0.55))
                            }
                            Spacer()
                            if variety.slug == selectedSlug {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(OrchardColor.good)
                            }
                        }
                    }
                    .foregroundStyle(OrchardColor.ink)
                }
                Button {
                    dismiss()
                    showCustom = true
                } label: {
                    Label("Add a custom variety", systemImage: "plus.circle.fill")
                        .font(OrchardFont.title(16))
                }
            }
            .searchable(text: $query, prompt: "Name or PLU")
            .navigationTitle("Variety")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}

struct CustomVarietySheet: View {
    var onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var category: ProduceCategory = .apple
    @State private var zone: FarmZone = .orchard
    @State private var form: PlantForm = .apple

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Category", selection: $category) {
                    ForEach(ProduceCategory.allCases, id: \.self) { item in
                        Text(item.singular).tag(item)
                    }
                }
                Picker("Where it grows", selection: $zone) {
                    ForEach(FarmZone.allCases, id: \.self) { item in
                        Text(item.title).tag(item)
                    }
                }
                Picker("Looks like", selection: $form) {
                    ForEach(PlantForm.allCases, id: \.self) { item in
                        Text(item.rawValue.capitalized).tag(item)
                    }
                }
            }
            .navigationTitle("Custom variety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: category) { _, newValue in
                applyDefaults(for: newValue)
            }
        }
    }

    private func applyDefaults(for category: ProduceCategory) {
        switch category {
        case .apple:
            zone = .orchard
            form = .apple
        case .pear:
            zone = .orchard
            form = .pear
        case .grape:
            zone = .trellis
            form = .grape
        case .tropical:
            zone = .orchard
            form = .mango
        case .vegetable:
            zone = .bed
            form = .carrot
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let colors = Self.colors(for: form)
        let variety = Variety(
            slug: "custom-\(UUID().uuidString.lowercased())",
            name: trimmed,
            aliases: [],
            categoryRaw: category.rawValue,
            zoneRaw: zone.rawValue,
            formRaw: form.rawValue,
            recordKindRaw: RecordKind.cultivar.rawValue,
            pluCodes: [],
            baseHex: colors.0,
            blushHex: colors.1,
            patternRaw: colors.2,
            blushAmount: 0.45,
            lenticels: false,
            skinVerified: false,
            skinNote: "Custom variety. Colours are a sketch.",
            regions: [],
            seasonMonths: [],
            seasonKindRaw: SeasonKind.unspecified.rawValue,
            seasonNote: "",
            whereToFind: "",
            fact: "",
            factStatusRaw: FactStatus.none.rawValue,
            isCustom: true
        )
        context.insert(variety)
        try? context.save()
        onCreate(variety.slug)
        dismiss()
    }

    private static func colors(for form: PlantForm) -> (String, String, String) {
        switch form {
        case .apple: ("#E23B3B", "#F2D44A", "blush")
        case .pear: ("#8FCB45", "#D6E07A", "solid")
        case .mango: ("#F2B434", "#E25A6A", "blush")
        case .grape: ("#8FB83A", "#D5E39A", "solid")
        case .carrot: ("#F08A1A", "#E26A12", "solid")
        case .tomato: ("#E23B2F", "#C42820", "solid")
        }
    }
}
