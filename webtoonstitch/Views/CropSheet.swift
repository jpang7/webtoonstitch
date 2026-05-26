import SwiftUI

struct CropSheet: View {
    let panel: Panel
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    @State private var containerSize: CGSize = .zero
    @State private var initialized = false

    // Image transform (pan + zoom on the source image, behind the crop window)
    @State private var imageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var panBaseOffset: CGSize = .zero
    @State private var pinchBaseScale: CGFloat = 1.0

    // Crop rect, in container (screen) coords
    @State private var cropRect: CGRect = .zero
    @State private var cropDragStart: CGRect?

    private let minScale: CGFloat = 0.25
    private let maxScale: CGFloat = 10.0

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()

                    if let image {
                        let baseFit = baseFitRect(imageSize: image.size, in: geo.size)

                        imageLayer(image: image, baseFit: baseFit)

                        DimMask(cropRect: cropRect)
                            .allowsHitTesting(false)

                        Rectangle()
                            .strokeBorder(Color.white, lineWidth: 2)
                            .frame(width: cropRect.width, height: cropRect.height)
                            .position(x: cropRect.midX, y: cropRect.midY)
                            .allowsHitTesting(false)

                        cornerHandle(.topLeft, container: geo.size)
                        cornerHandle(.topRight, container: geo.size)
                        cornerHandle(.bottomLeft, container: geo.size)
                        cornerHandle(.bottomRight, container: geo.size)
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .onAppear {
                    containerSize = geo.size
                    initializeIfReady(container: geo.size)
                }
                .onChange(of: geo.size) { _, newSize in
                    containerSize = newSize
                    if !initialized { initializeIfReady(container: newSize) }
                }
                .onChange(of: image) { _, _ in
                    if !initialized { initializeIfReady(container: geo.size) }
                }
            }
            .navigationTitle("Crop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset", action: reset)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: save).bold()
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .onAppear { loadImage() }
    }

    // MARK: - Image layer

    @ViewBuilder
    private func imageLayer(image: UIImage, baseFit: CGRect) -> some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: baseFit.width, height: baseFit.height)
            .scaleEffect(imageScale, anchor: .center)
            .offset(imageOffset)
            .position(x: baseFit.midX, y: baseFit.midY)
            .gesture(
                SimultaneousGesture(
                    imagePanGesture(),
                    imageZoomGesture()
                )
            )
    }

    private func imagePanGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                imageOffset = CGSize(
                    width: panBaseOffset.width + value.translation.width,
                    height: panBaseOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                panBaseOffset = imageOffset
            }
    }

    private func imageZoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                imageScale = clamp(pinchBaseScale * value, minScale, maxScale)
            }
            .onEnded { _ in
                pinchBaseScale = imageScale
            }
    }

    // MARK: - Crop corner handles

    private func cornerHandle(_ corner: Corner, container: CGSize) -> some View {
        let pos = cornerPoint(corner)
        return ZStack {
            Color.clear
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            Circle()
                .fill(Color.white)
                .frame(width: 20, height: 20)
                .shadow(radius: 2)
        }
        .position(x: pos.x, y: pos.y)
        .gesture(cornerGesture(corner, container: container))
    }

    private func cornerGesture(_ corner: Corner, container: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if cropDragStart == nil { cropDragStart = cropRect }
                guard let start = cropDragStart else { return }
                let minSide: CGFloat = 40

                var r = start
                let right = start.maxX
                let bottom = start.maxY
                let dx = value.translation.width
                let dy = value.translation.height

                switch corner {
                case .topLeft:
                    let newX = clamp(start.minX + dx, 0, right - minSide)
                    let newY = clamp(start.minY + dy, 0, bottom - minSide)
                    r = CGRect(x: newX, y: newY, width: right - newX, height: bottom - newY)
                case .topRight:
                    let newY = clamp(start.minY + dy, 0, bottom - minSide)
                    let newW = clamp(start.width + dx, minSide, container.width - start.minX)
                    r = CGRect(x: start.minX, y: newY, width: newW, height: bottom - newY)
                case .bottomLeft:
                    let newX = clamp(start.minX + dx, 0, right - minSide)
                    let newH = clamp(start.height + dy, minSide, container.height - start.minY)
                    r = CGRect(x: newX, y: start.minY, width: right - newX, height: newH)
                case .bottomRight:
                    let newW = clamp(start.width + dx, minSide, container.width - start.minX)
                    let newH = clamp(start.height + dy, minSide, container.height - start.minY)
                    r = CGRect(x: start.minX, y: start.minY, width: newW, height: newH)
                }
                cropRect = r
            }
            .onEnded { _ in cropDragStart = nil }
    }

    private func cornerPoint(_ c: Corner) -> CGPoint {
        switch c {
        case .topLeft:     return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case .topRight:    return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case .bottomLeft:  return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        case .bottomRight: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        }
    }

    // MARK: - Initialization / reset / save

    private func loadImage() {
        guard let project = panel.project else { return }
        let url = ProjectStore.shared.panelFileURL(
            for: project,
            filename: panel.assetFilename
        )
        image = UIImage(contentsOfFile: url.path)
    }

    private func initializeIfReady(container: CGSize) {
        guard let image, container.width > 0, container.height > 0 else { return }
        let baseFit = baseFitRect(imageSize: image.size, in: container)

        cropRect = CGRect(
            x: baseFit.minX + baseFit.width * CGFloat(panel.cropX),
            y: baseFit.minY + baseFit.height * CGFloat(panel.cropY),
            width: baseFit.width * CGFloat(panel.cropW),
            height: baseFit.height * CGFloat(panel.cropH)
        )
        imageScale = 1
        imageOffset = .zero
        panBaseOffset = .zero
        pinchBaseScale = 1
        initialized = true
    }

    private func reset() {
        guard let image else { return }
        let baseFit = baseFitRect(imageSize: image.size, in: containerSize)
        cropRect = baseFit
        imageScale = 1
        imageOffset = .zero
        panBaseOffset = .zero
        pinchBaseScale = 1
    }

    private func save() {
        guard let image else { dismiss(); return }
        let baseFit = baseFitRect(imageSize: image.size, in: containerSize)
        let imgRect = currentImageRect(baseFit: baseFit)
        guard imgRect.width > 0, imgRect.height > 0 else { dismiss(); return }

        let nx = clamp(Double((cropRect.minX - imgRect.minX) / imgRect.width), 0, 1)
        let ny = clamp(Double((cropRect.minY - imgRect.minY) / imgRect.height), 0, 1)
        let nMaxX = clamp(Double((cropRect.maxX - imgRect.minX) / imgRect.width), 0, 1)
        let nMaxY = clamp(Double((cropRect.maxY - imgRect.minY) / imgRect.height), 0, 1)
        let nw = max(0.01, nMaxX - nx)
        let nh = max(0.01, nMaxY - ny)

        panel.cropX = nx
        panel.cropY = ny
        panel.cropW = nw
        panel.cropH = nh
        panel.project?.updatedAt = Date()
        dismiss()
    }

    // MARK: - Geometry

    private func baseFitRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0
        else { return .zero }
        let imgAspect = imageSize.width / imageSize.height
        let containerAspect = container.width / container.height
        if imgAspect > containerAspect {
            let h = container.width / imgAspect
            return CGRect(
                x: 0,
                y: (container.height - h) / 2,
                width: container.width,
                height: h
            )
        } else {
            let w = container.height * imgAspect
            return CGRect(
                x: (container.width - w) / 2,
                y: 0,
                width: w,
                height: container.height
            )
        }
    }

    /// Where the image is actually drawn on screen, accounting for scale + offset.
    private func currentImageRect(baseFit: CGRect) -> CGRect {
        let w = baseFit.width * imageScale
        let h = baseFit.height * imageScale
        let x = baseFit.midX - w / 2 + imageOffset.width
        let y = baseFit.midY - h / 2 + imageOffset.height
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T {
        max(lo, min(hi, v))
    }

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
}

// MARK: - Dim mask outside the crop rect

private struct DimMask: View {
    let cropRect: CGRect

    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geo.size))
                path.addRect(cropRect)
            }
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        }
        .ignoresSafeArea()
    }
}
