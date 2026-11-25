import SwiftUI
import UniformTypeIdentifiers
import RicettarioCore

// MARK: - Surfaces

/// Material 3 card: tonal surface, large continuous corners.
struct M3Card<Content: View>: View {
    @Environment(\.m3) private var m3
    var color: Color?
    var padding: CGFloat
    var corner: CGFloat
    let content: Content

    init(color: Color? = nil, padding: CGFloat = 16, corner: CGFloat = 26, @ViewBuilder content: () -> Content) {
        self.color = color
        self.padding = padding
        self.corner = corner
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color ?? m3.surfaceContainerLow, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

struct SectionTitle: View {
    @Environment(\.m3) private var m3
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.m3TitleLarge).foregroundStyle(m3.onSurface)
            Spacer()
            if let trailing {
                Text(trailing).font(.m3LabelMedium).foregroundStyle(m3.onSurfaceVariant)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }
}

// MARK: - Buttons

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct PillButton: View {
    let title: String
    let icon: String
    let tones: Tones
    var filled = true
    var height: CGFloat = 54
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 18, weight: .semibold))
                Text(title).font(.m3TitleMedium).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(filled ? tones.onAccent : tones.onContainer)
            .frame(maxWidth: .infinity, minHeight: height)
            .padding(.horizontal, 8)
            .background(filled ? tones.accent : tones.container, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

struct Chip: View {
    @Environment(\.m3) private var m3
    let title: String
    var icon: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                } else if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(.m3LabelLarge).lineLimit(1)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .foregroundStyle(selected ? m3.onSecondaryContainer : m3.onSurfaceVariant)
            .background(selected ? m3.secondaryContainer : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.clear : m3.outlineVariant, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.m3Effects, value: selected)
    }
}

/// Round icon button (− / + steppers, toolbar-like actions).
struct RoundIconButton: View {
    let icon: String
    let tones: Tones
    var size: CGFloat = 44
    var filled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(filled ? tones.onAccent : tones.onContainer)
                .frame(width: size, height: size)
                .background(filled ? tones.accent : tones.container, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - Toast and empty state

struct ToastView: View {
    @Environment(\.m3) private var m3
    let toast: Toast

    var body: some View {
        let tones: Tones = {
            switch toast.style {
            case .success: return m3.successTones
            case .info: return m3.neutral
            case .error: return m3.errorTones
            }
        }()
        HStack(spacing: 10) {
            Image(systemName: toast.icon).font(.system(size: 15, weight: .bold))
            Text(toast.message).font(.m3LabelLarge)
        }
        .foregroundStyle(tones.onContainer)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(tones.container, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

struct EmptyStateView: View {
    @Environment(\.m3) private var m3
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            IconBadge(icon: icon, tones: m3.primaryTones, size: 88, cookie: true)
            Text(title).font(.m3TitleLarge).foregroundStyle(m3.onSurface).multilineTextAlignment(.center)
            Text(message).font(.m3BodyMedium).foregroundStyle(m3.onSurfaceVariant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .padding(.horizontal, 24)
    }
}

struct TagLabel: View {
    let text: String
    var icon: String?
    let tones: Tones

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
            Text(text).font(.m3LabelMedium).lineLimit(1)
        }
        .foregroundStyle(tones.onContainer)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tones.container, in: Capsule())
    }
}

// MARK: - Photos

/// A stored photo (file in Application Support/Photos), or a placeholder.
struct StoredPhoto: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    let name: String?
    var placeholder: String = "🍽️"
    var contentMode: ContentMode = .fill

    var body: some View {
        ZStack {
            if let name, let img = model.image(name) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(m3.primaryContainer)
                Text(placeholder).font(.system(size: 40))
            }
        }
        .clipped()
    }
}

/// Recipe cover: photo or emoji on a tonal tile.
struct RecipeThumb: View {
    @Environment(\.m3) private var m3
    let recipe: Recipe
    var size: CGFloat = 64
    var corner: CGFloat = 18

    var body: some View {
        StoredPhoto(name: recipe.photo, placeholder: recipe.emoji)
            .font(.system(size: size * 0.5))
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}

// MARK: - Layout

/// Wrapping row of chips/tags.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Files

/// Plain file wrapper for `fileExporter` (backup JSON).
struct DataFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let ricetta = UTType(exportedAs: "com.garoth93.ricettario.recipe", conformingTo: .json)
}

// MARK: - Formatting helpers

extension ScaledIngredient {
    func amountText(_ prefs: UnitPreferences) -> String {
        guard let a = amount else { return "q.b." }
        return UnitConverter.display(base: a, entryUnit: ingredient.unit, density: ingredient.density, prefs: prefs).text
    }

    func exactText(_ prefs: UnitPreferences) -> String? {
        guard let e = exact else { return nil }
        return Fmt.number(e, digits: 2)
    }
}

extension RecipeIngredient {
    func amountText(_ prefs: UnitPreferences) -> String {
        guard let a = amount else { return "q.b." }
        return UnitConverter.display(base: a, entryUnit: unit, density: density, prefs: prefs).text
    }
}

func peopleText(_ n: Double) -> String {
    let rounded = abs(n - n.rounded()) < 0.01
    let s = rounded ? "\(Int(n.rounded()))" : Fmt.number(n, digits: 1)
    return "\(s) \(s == "1" ? "persona" : "persone")"
}
