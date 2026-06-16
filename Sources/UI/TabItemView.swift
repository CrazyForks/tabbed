import SwiftUI

/// A single pill in the tab strip: app icon + title, with active / hover styling.
struct TabItemView: View {
    let tab: TabDescriptor
    let isActive: Bool
    let isHovered: Bool
    let width: CGFloat
    let onClose: () -> Void

    @State private var closeHovered = false

    var body: some View {
        ZStack {
            // Favicon + title, centered like Safari.
            HStack(spacing: 6) {
                icon

                Text(tab.title.isEmpty ? tab.appName : tab.title)
                    .font(.system(size: Theme.titleSize, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white.opacity(textOpacity))
            }
            // Leave room so the centered title never collides with the close button.
            .padding(.horizontal, 22)

            // Close button overlaid on the leading edge (appears on hover only,
            // so the resting tab stays clean); as an overlay it doesn't shift
            // the centered title.
            if isHovered {
                HStack {
                    closeButton
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8)
            }
        }
        .frame(width: width, height: Theme.tabHeight)
        .pillHighlight(isActive: isActive, isHovered: isHovered)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let img = tab.appIcon() {
            Image(nsImage: img)
                .resizable()
                .frame(width: Theme.iconSize, height: Theme.iconSize)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(.white.opacity(0.2))
                .frame(width: Theme.iconSize, height: Theme.iconSize)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(closeHovered ? 0.95 : 0.6))
                .frame(width: 15, height: 15)
                .background(
                    Circle().fill(.white.opacity(closeHovered ? 0.18 : 0.0))
                )
        }
        .buttonStyle(.plain)
        .onHover { closeHovered = $0 }
    }

    private var textOpacity: Double {
        if isActive { return Theme.textActive }
        if isHovered { return Theme.textHover }
        return Theme.textIdle
    }
}

private extension View {
    /// Selected/hovered tab highlight: a translucent capsule drawn on the glass
    /// bar (the Safari/Tahoe pattern). A plain fill — not a nested glass effect —
    /// so it never intercepts the tab's tap or collapse its layout.
    func pillHighlight(isActive: Bool, isHovered: Bool) -> some View {
        let shape = Capsule(style: .continuous)
        let fill = isActive ? Theme.fillActive : (isHovered ? Theme.fillHover : Theme.fillIdle)
        return self
            .background(shape.fill(.white.opacity(fill)))
            .overlay(shape.stroke(.white.opacity(isActive ? Theme.strokeActive : Theme.strokeIdle),
                                  lineWidth: 1))
    }
}
