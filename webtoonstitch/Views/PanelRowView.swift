import SwiftUI

struct PanelRowView: View {
    let panel: Panel
    let displayWidth: CGFloat
    /// Overlap of the *next* panel down on this one, in display (screen) px.
    /// Used to shrink our layout frame so the next panel comes up to cover
    /// our bottom edge, producing the visual overlap.
    let nextOverlapPx: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    @State private var image: UIImage?

    private var aspect: CGFloat {
        guard panel.width > 0, panel.height > 0 else { return 3.0 / 4.0 }
        return CGFloat(panel.width) / CGFloat(panel.height)
    }

    private var naturalDisplayHeight: CGFloat {
        guard aspect > 0 else { return 0 }
        return displayWidth / aspect
    }

    /// Layout height = natural - next panel's overlap.
    /// If the next panel overlaps us by N px, we tell the VStack our height
    /// is N less, so it places the next panel up to cover our last N px.
    /// Visually we still draw the full image (it overflows our layout frame),
    /// and the next panel draws on top because it's later in z-order.
    private var layoutHeight: CGFloat {
        max(1, naturalDisplayHeight - nextOverlapPx)
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
                .frame(width: displayWidth, height: naturalDisplayHeight)

            if isSelected {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: displayWidth, height: naturalDisplayHeight)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: displayWidth, height: layoutHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear { load() }
        .onDisappear { image = nil }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Color.gray.opacity(0.15)
                .overlay(ProgressView())
        }
    }

    private func load() {
        guard let project = panel.project else { return }
        let url = ProjectStore.shared.panelFileURL(
            for: project,
            filename: panel.assetFilename
        )
        image = PanelImageCache.shared.image(forID: panel.id, fileURL: url)
    }
}
