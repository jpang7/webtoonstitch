import SwiftUI

struct PanelRowView: View {
    let panel: Panel

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(panelAspect, contentMode: .fit)
            } else {
                Color.gray.opacity(0.15)
                    .aspectRatio(panelAspect, contentMode: .fit)
                    .overlay(ProgressView())
            }
        }
        .onAppear { load() }
        .onDisappear { image = nil }
    }

    private var panelAspect: CGFloat {
        guard panel.width > 0, panel.height > 0 else { return 3.0 / 4.0 }
        return CGFloat(panel.width) / CGFloat(panel.height)
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
