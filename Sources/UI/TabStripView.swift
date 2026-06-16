import SwiftUI

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

    private var bar: some View {
        content.frame(height: Theme.stripHeight).glassBar()
    }

    private var isShowingPill: Bool { model.compact && !model.hovered }

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

    private func tabLayout(forContainerWidth containerWidth: CGFloat) -> (width: CGFloat, overflowing: Bool) {
        let count = CGFloat(max(model.tabs.count, 1))
        let totalSpacing = Theme.tabSpacing * (count - 1)
        let available = max(containerWidth - totalSpacing, 0)
        let ideal = available / count
        let overflowing = ideal < Theme.tabMinWidth
        return (overflowing ? Theme.tabMinWidth : ideal, overflowing)
    }
}

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
    /// Liquid Glass on macOS 26+, HUD material fallback otherwise.
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
