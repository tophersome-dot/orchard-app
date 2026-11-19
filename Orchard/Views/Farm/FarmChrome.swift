import SwiftUI

struct StorageStack: Identifiable, Equatable {
    var id: String
    var title: String
    var systemImage: String
    var sprite: String?
    var count: Int
    var sampleID: UUID
}

struct FarmLevelHeader: View {
    var level: Int
    var progress: Double
    var detail: String
    var soundOn: Bool
    var editing: Bool
    var onSound: () -> Void
    var onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.black.opacity(0.08), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.04, min(1, progress)))
                    .stroke(OrchardColor.grassDeep, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(level)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(OrchardColor.ink)
            }
            .frame(width: 36, height: 36)
            .accessibilityLabel("Island level \(level)")
            VStack(alignment: .leading, spacing: 1) {
                Text("Chris's Orchard")
                    .font(.system(size: 16, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(OrchardColor.ink)
            Spacer(minLength: 0)
            Button(action: onSound) {
                Image(systemName: soundOn ? "speaker.wave.2" : "speaker.slash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(OrchardColor.ink)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(soundOn ? "Sound on" : "Sound off")
            Button(editing ? "Done" : "Edit", action: onEdit)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OrchardColor.grassDeep)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct FarmEditToolbar: View {
    var moveOn: Bool
    var paintOn: Bool
    var axeOn: Bool
    var storageOn: Bool
    var canUndo: Bool
    var onMove: () -> Void
    var onPaint: () -> Void
    var onAxe: () -> Void
    var onStorage: () -> Void
    var onUndo: () -> Void
    var onDone: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            tool("Move", "arrow.up.and.down.and.arrow.left.and.right", on: moveOn, enabled: true, action: onMove)
            tool("Paint", "paintbrush", on: paintOn, enabled: true, action: onPaint)
            tool("Axe", "axe", on: axeOn, enabled: true, action: onAxe)
            tool("Store", "archivebox", on: storageOn, enabled: true, action: onStorage)
            tool("Undo", "arrow.uturn.backward", on: false, enabled: canUndo, action: onUndo)
            tool("Done", "checkmark", on: false, enabled: true, action: onDone)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func tool(_ title: String, _ symbol: String, on: Bool, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                if symbol == "axe" {
                    AxeIcon()
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(height: 18)
                }
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? OrchardColor.grassDeep : (enabled ? OrchardColor.ink : Color.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(on ? Color.white.opacity(0.72) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
        .accessibilityLabel(title)
    }
}

/// A thin axe: handle plus a curved blade. SF Symbols has no axe glyph.
struct AxeIcon: View {
    var body: some View {
        Canvas { context, size in
            var handle = Path()
            handle.move(to: CGPoint(x: size.width * 0.58, y: size.height * 0.22))
            handle.addLine(to: CGPoint(x: size.width * 0.30, y: size.height * 0.92))
            context.stroke(handle, with: .foreground, style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            var blade = Path()
            blade.move(to: CGPoint(x: size.width * 0.46, y: size.height * 0.20))
            blade.addQuadCurve(
                to: CGPoint(x: size.width * 0.92, y: size.height * 0.30),
                control: CGPoint(x: size.width * 0.78, y: size.height * 0.0)
            )
            blade.addQuadCurve(
                to: CGPoint(x: size.width * 0.52, y: size.height * 0.46),
                control: CGPoint(x: size.width * 0.86, y: size.height * 0.52)
            )
            blade.closeSubpath()
            context.fill(blade, with: .foreground)
        }
    }
}

struct FarmSelectionButtons: View {
    var canFlip: Bool
    var canStore: Bool
    var onMove: () -> Void
    var onFlip: () -> Void
    var onRotate: () -> Void
    var onStore: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            round("Move", "arrow.up.and.down.and.arrow.left.and.right", action: onMove)
            if canFlip {
                round("Flip", "flip.horizontal", action: onFlip)
                round("Rotate", "rotate.right", action: onRotate)
            }
            if canStore {
                round("Store", "archivebox", action: onStore)
                round("Delete", "trash", action: onDelete)
            }
        }
    }

    private func round(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(OrchardColor.ink)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

struct FarmStorageTray: View {
    var stacks: [StorageStack]
    var onClose: () -> Void
    var onTap: (UUID) -> Void
    var onDrag: (UUID, CGPoint, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Storage")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OrchardColor.ink)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(OrchardColor.ink)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
            }
            if stacks.isEmpty {
                Text("Nothing stored yet. Select something on the farm and tap Store.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(stacks) { stack in
                            row(stack)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func row(_ stack: StorageStack) -> some View {
        let body = VStack(spacing: 4) {
            if let sprite = stack.sprite {
                Image(sprite)
                    .resizable()
                    .interpolation(.medium)
                    .scaledToFit()
                    .frame(width: 36, height: 36)
            } else {
                Image(systemName: stack.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            Text(stack.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Text("×\(stack.count)")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(OrchardColor.ink)
        .frame(width: 72)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 8, coordinateSpace: .named("farm"))
                .onChanged { value in
                    onDrag(stack.sampleID, value.location, false)
                }
                .onEnded { value in
                    onDrag(stack.sampleID, value.location, true)
                }
        )
        .onTapGesture { onTap(stack.sampleID) }
        return body
    }
}

struct FarmMinimap: View {
    var ground: Set<FarmTile>
    var water: Set<FarmTile>
    var woods: Set<FarmTile>
    var farm: Set<FarmTile>
    var camera: FarmCamera
    var mapSize: CGSize
    var onJump: (CGPoint) -> Void
    var onHide: () -> Void

    private let size = CGSize(width: 124, height: 92)

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button(action: onHide) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(OrchardColor.ink)
                    .frame(width: 26, height: 22)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Hide map")
            Canvas { context, canvas in
                draw(in: context, canvas: canvas)
            }
            .frame(width: size.width, height: size.height)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if let world = worldPoint(at: value.location) { onJump(world) }
                    }
            )
        }
    }

    private func draw(in context: GraphicsContext, canvas: CGSize) {
        guard let fit = fitTransform(in: canvas) else { return }
        fill(ground, color: Color(red: 0.56, green: 0.78, blue: 0.34), fit: fit, in: context)
        fill(woods, color: Color(red: 0.24, green: 0.48, blue: 0.22), fit: fit, in: context)
        fill(water, color: Color(red: 0.29, green: 0.62, blue: 0.82), fit: fit, in: context)
        fill(farm, color: Color(red: 0.93, green: 0.84, blue: 0.45), fit: fit, in: context)
        var path = Path()
        let corners = [
            CGPoint.zero,
            CGPoint(x: mapSize.width, y: 0),
            CGPoint(x: mapSize.width, y: mapSize.height),
            CGPoint(x: 0, y: mapSize.height)
        ]
        for (index, corner) in corners.enumerated() {
            let world = camera.worldPoint(corner, in: mapSize)
            let point = fit.point(world)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        context.stroke(path, with: .color(Color.white), lineWidth: 1.5)
    }

    private func fill(_ tiles: Set<FarmTile>, color: Color, fit: Fit, in context: GraphicsContext) {
        guard !tiles.isEmpty else { return }
        var path = Path()
        let step = max(1, tiles.count / 700)
        for (index, tile) in tiles.enumerated() where index % step == 0 {
            let center = fit.point(IsoMap.center(tile))
            let rect = CGRect(x: center.x - 1.3, y: center.y - 0.8, width: 2.6, height: 1.6)
            path.addEllipse(in: rect)
        }
        context.fill(path, with: .color(color))
    }

    private func worldPoint(at location: CGPoint) -> CGPoint? {
        guard let fit = fitTransform(in: size) else { return nil }
        return fit.world(location)
    }

    private struct Fit {
        var minX: CGFloat
        var minY: CGFloat
        var scale: CGFloat
        var origin: CGPoint

        func point(_ world: CGPoint) -> CGPoint {
            CGPoint(x: origin.x + (world.x - minX) * scale, y: origin.y + (world.y - minY) * scale)
        }

        func world(_ local: CGPoint) -> CGPoint {
            CGPoint(x: minX + (local.x - origin.x) / scale, y: minY + (local.y - origin.y) / scale)
        }
    }

    private func fitTransform(in canvas: CGSize) -> Fit? {
        let tiles = ground.union(water)
        let points = tiles.map { IsoMap.center($0) }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        let spanX = max(maxX - minX, 1)
        let spanY = max(maxY - minY, 1)
        let scale = min((canvas.width - 16) / spanX, (canvas.height - 16) / spanY)
        let usedW = spanX * scale
        let usedH = spanY * scale
        return Fit(
            minX: minX,
            minY: minY,
            scale: scale,
            origin: CGPoint(x: (canvas.width - usedW) / 2, y: (canvas.height - usedH) / 2)
        )
    }
}

enum FarmHintStep: Int {
    case pinch = 0
    case hold = 1
    case edit = 2

    var text: String {
        switch self {
        case .pinch: "Pinch to zoom"
        case .hold: "Press and hold to move"
        case .edit: "Edit to decorate"
        }
    }
}

struct FarmHintChip: View {
    var step: FarmHintStep
    var onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Text(step.text)
                    .font(.system(size: 13, weight: .semibold))
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(OrchardColor.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hint-\(step.rawValue)")
    }
}

struct FarmMinimapRestore: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OrchardColor.ink)
                .frame(width: 26, height: 22)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show map")
    }
}
