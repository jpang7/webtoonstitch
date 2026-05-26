import SwiftUI

struct PanelRowView: View {
    let panel: Panel
    /// The on-screen width of the canvas (e.g. screen width).
    let displayWidth: CGFloat
    /// Overlap of the *next* panel down on this one, in display (screen) px.
    let nextOverlapPx: CGFloat
    let isSelected: Bool
    let onTap: () -> Void

    @State private var image: UIImage?

    private var cropX: CGFloat { CGFloat(panel.cropX) }
    private var cropY: CGFloat { CGFloat(panel.cropY) }
    private var cropW: CGFloat { max(0.0001, CGFloat(panel.cropW)) }
    private var cropH: CGFloat { max(0.0001, CGFloat(panel.cropH)) }

    /// Aspect ratio (h/w) of the source image at its natural orientation.
    private var imageAspect: CGFloat {
        guard panel.width > 0 else { return 1 }
        return CGFloat(panel.height) / CGFloat(panel.width)
    }

    // The cropped region fills the canvas width. Its height is determined by
    // the cropped region's aspect ratio (h/w = imageAspect * cropH/cropW).
    private var finalDisplayWidth: CGFloat { displayWidth }
    private var finalDisplayHeight: CGFloat {
        displayWidth * imageAspect * cropH / cropW
    }

    // The source image is rendered scaled up by 1/cropW so that the crop
    // window's width (cropW * scaled width) equals the canvas width.
    private var scaledImageWidth: CGFloat { displayWidth / cropW }
    private var scaledImageHeight: CGFloat { displayWidth * imageAspect / cropW }

    /// Layout height = final cropped height minus the next panel's overlap.
    /// The image overflows the bottom of the layout frame, and the next
    /// sibling in the LazyVStack covers it, producing the overlap visual.
    private var layoutHeight: CGFloat {
        max(1, finalDisplayHeight - nextOverlapPx)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            croppedImage
                .frame(
                    width: finalDisplayWidth,
                    height: finalDisplayHeight,
                    alignment: .topLeading
                )
                .clipped()

            if isSelected {
                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(
                        width: finalDisplayWidth,
                        height: finalDisplayHeight
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(width: finalDisplayWidth, height: layoutHeight, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onAppear { load() }
        .onDisappear { image = nil }
    }

    @ViewBuilder
    private var croppedImage: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .interpolation(.medium)
                .frame(width: scaledImageWidth, height: scaledImageHeight)
                .offset(
                    x: -cropX * scaledImageWidth,
                    y: -cropY * scaledImageHeight
                )
        } else {
            Color.gray.opacity(0.15)
                .frame(width: finalDisplayWidth, height: finalDisplayHeight)
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
