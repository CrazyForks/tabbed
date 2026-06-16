import SwiftUI

/// The row of tabs hosted inside a `TabBarPanel`. Pure presentation: it renders
/// `model.tabs` and routes clicks back through the view model.
struct TabStripView: View {
    @ObservedObject var model: TabGroupViewModel
    @State private var hoveredID: WindowID?
    @State private var dragStartMouse: CGPoint?

    var body: some View {
        bar
            .contentShape(Rectangle())
            .onTapGesture { model.activateActive() }
            .gesture(moveGesture)
            .animation(.easeOut(duration: 0.18), value: isShowingPill)
    }

    /// The glass bar itself. In compact mode it's re-inset inside the panel and
    /// surrounded by the frosted matte halo (`compactMatte`) that fills the gap
    /// out to the window edges; otherwise it fills the panel as before.
    @ViewBuilder
    private var bar: some View {
        let core = content.frame(height: Theme.stripHeight).glassBar()
        if model.compact {
            core
                .padding(Theme.compactInset)
                .background(compactMatte)
        } else {
            core
        }
    }

    /// A slight blur of the window content behind the bar, drawn in the inset gap
    /// around it (concentric with the bar's curve). Lifts the bar off busy
    /// backgrounds without covering the window like a solid frame would.
    private var compactMatte: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.compactMatteCornerRadius, style: .continuous)
        return ZStack {
            VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
            shape.fill(.black.opacity(Theme.compactMatteTint))
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.06), lineWidth: 0.5))
    }

    private var isShowingPill: Bool { model.compact && !model.hovered }

    /// Compact icon-only pill at rest (no room above); full bar otherwise or
    /// while hovered.
    @ViewBuilder
    private var content: some View {
        if isShowingPill {
            compactPill.transition(.opacity)
        } else {
            fullBar.transition(.opacity)
        }
    }

    private var fullBar: some View {
        GeometryReader { proxy in
            let layout = tabLayout(forContainerWidth: proxy.size.width)
            if layout.overflowing {
                ScrollView(.horizontal, showsIndicators: false) {
                    tabRow(width: layout.width)
                }
            } else {
                tabRow(width: layout.width)
            }
        }
        .padding(Theme.stripPadding)
    }

    /// The row of equal-width tab pills filling the available width.
    private func tabRow(width: CGFloat) -> some View {
        HStack(spacing: Theme.tabSpacing) {
            ForEach(model.tabs) { tab in
                TabItemView(
                    tab: tab,
                    isActive: tab.id == model.activeID,
                    isHovered: tab.id == hoveredID,
                    width: width,
                    onClose: { model.close(tab.id) }
                )
                .onHover { hoveredID = $0 ? tab.id : (hoveredID == tab.id ? nil : hoveredID) }
                .onTapGesture { model.select(tab.id) }
            }
        }
        .frame(height: Theme.tabHeight)
    }

    private var compactPill: some View {
        HStack(spacing: 4) {
            ForEach(model.tabs) { tab in
                compactIcon(for: tab)
            }
        }
        .padding(.horizontal, Theme.compactPillPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func compactIcon(for tab: TabDescriptor) -> some View {
        let isActive = tab.id == model.activeID
        Group {
            if let img = tab.appIcon() {
                Image(nsImage: img).resizable()
            } else {
                RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.2))
            }
        }
        .frame(width: Theme.compactIconSize, height: Theme.compactIconSize)
        .opacity(isActive ? 1.0 : 0.45)
    }

    private var moveGesture: some Gesture {
        // The panel moves during the drag, so use screen coordinates.
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in
                let mouse = NSEvent.mouseLocation
                if dragStartMouse == nil {
                    dragStartMouse = mouse
                    model.moveBegan()
                }
                let start = dragStartMouse ?? mouse
                model.moveChanged(CGSize(width: mouse.x - start.x,
                                         height: mouse.y - start.y))
            }
            .onEnded { _ in
                dragStartMouse = nil
                model.moveEnded()
            }
    }

    /// Split the strip evenly across tabs so the row always fills the bar.
    /// `overflowing` is true once an equal share would fall below the minimum
    /// width — then tabs pin to the floor and the caller scrolls horizontally.
    private func tabLayout(forContainerWidth containerWidth: CGFloat) -> (width: CGFloat, overflowing: Bool) {
        let count = CGFloat(max(model.tabs.count, 1))
        let totalSpacing = Theme.tabSpacing * (count - 1)
        let available = max(containerWidth - totalSpacing, 0)
        let ideal = available / count
        let overflowing = ideal < Theme.tabMinWidth
        return (overflowing ? Theme.tabMinWidth : ideal, overflowing)
    }
}

/// Thin wrapper so SwiftUI can use an `NSVisualEffectView` as a background.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blending
    }
}

private extension View {
    /// The strip's container surface: real Liquid Glass on macOS 26+, with the
    /// HUD material as a fallback on older systems. Liquid Glass `.regular` is
    /// backdrop-adaptive and brightens to white over a light desktop, so a dark
    /// translucent wash is layered *over* the glass (behind the tabs) to anchor
    /// it dark deterministically — the glass still shows through at ~50%.
    @ViewBuilder
    func glassBar() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.stripCornerRadius, style: .continuous)
        if #available(macOS 26.0, *) {
            self
                .background(shape.fill(.black.opacity(0.45)))
                .glassEffect(.regular, in: shape)
        } else {
            self.background(
                ZStack {
                    VisualEffectBackground(material: .hudWindow, blending: .behindWindow)
                    shape.fill(.black.opacity(0.18))
                }
                .clipShape(shape)
                .overlay(shape.stroke(.white.opacity(0.10), lineWidth: 1))
            )
        }
    }
}
