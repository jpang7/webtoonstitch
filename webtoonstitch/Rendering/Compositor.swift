import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Sendable snapshots (so we can hop into a detached Task safely)

struct PanelSnapshot: Sendable {
    let id: UUID
    let order: Int
    let assetURL: URL
    let width: Int
    let height: Int
    let cropX: Double
    let cropY: Double
    let cropW: Double
    let cropH: Double
    let overlapWithPrevious: Double
}

struct ProjectSnapshot: Sendable {
    let id: UUID
    let name: String
    let canvasWidth: Int
    let backgroundHex: String
    let panels: [PanelSnapshot]
}

@MainActor
extension ProjectSnapshot {
    init(project: Project) {
        let sorted = project.panels.sorted { $0.order < $1.order }
        let panelSnapshots = sorted.map { p in
            PanelSnapshot(
                id: p.id,
                order: p.order,
                assetURL: ProjectStore.shared.panelFileURL(
                    for: project,
                    filename: p.assetFilename
                ),
                width: p.width,
                height: p.height,
                cropX: p.cropX,
                cropY: p.cropY,
                cropW: p.cropW,
                cropH: p.cropH,
                overlapWithPrevious: p.overlapWithPrevious
            )
        }
        self.init(
            id: project.id,
            name: project.name,
            canvasWidth: project.canvasWidth,
            backgroundHex: project.backgroundHex,
            panels: panelSnapshots
        )
    }
}

// MARK: - Errors

enum CompositorError: LocalizedError {
    case noPanels
    case canvasTooLarge(height: Int)
    case bitmapContextFailed
    case sourceImageMissing(URL)
    case croppingFailed
    case encodingFailed
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noPanels:
            return "There are no panels to export."
        case .canvasTooLarge(let height):
            return "Canvas would be \(height)px tall, which is too large to export safely. Try splitting the project or reducing crops."
        case .bitmapContextFailed:
            return "Couldn't allocate the export canvas (out of memory)."
        case .sourceImageMissing(let url):
            return "Missing panel image: \(url.lastPathComponent)"
        case .croppingFailed:
            return "Couldn't apply a panel crop while drawing."
        case .encodingFailed:
            return "Couldn't encode the final PNG."
        case .cancelled:
            return "Export cancelled."
        }
    }
}

// MARK: - Compositor

enum Compositor {

    /// Hard cap on the output canvas height in pixels. 65,536 is a safe upper
    /// bound for CGImage/PNG paths on iOS; we'll surface a clear error past it.
    nonisolated static let maxCanvasHeight: Int = 65_536

    struct Layout: Sendable {
        let panel: PanelSnapshot
        let topY: Double
        let displayHeight: Double
    }

    /// Computes y-position and displayed height (in canvas px) for each panel,
    /// honoring crop scale-up and overlap-with-previous.
    nonisolated static func computeLayout(
        panels: [PanelSnapshot],
        canvasWidth: Int
    ) -> (layouts: [Layout], totalHeight: Double) {
        var layouts: [Layout] = []
        var cursor: Double = 0
        var maxBottom: Double = 0

        for (idx, panel) in panels.enumerated() {
            guard panel.width > 0, panel.cropW > 0 else { continue }
            let aspect = Double(panel.height) / Double(panel.width)
            let displayHeight = Double(canvasWidth) * aspect * panel.cropH / panel.cropW
            let topY: Double = idx == 0 ? 0 : cursor - panel.overlapWithPrevious
            layouts.append(Layout(panel: panel, topY: topY, displayHeight: displayHeight))
            cursor = topY + displayHeight
            maxBottom = max(maxBottom, cursor)
        }

        return (layouts, max(1, maxBottom))
    }

    /// Renders the project into a PNG at `destinationURL`. Calls `progress`
    /// with a value 0...1 after each panel is drawn (off the main actor).
    /// Honors `Task.isCancelled`.
    nonisolated static func export(
        snapshot: ProjectSnapshot,
        destinationURL: URL,
        progress: @Sendable (Double) -> Void
    ) throws -> URL {
        let canvasWidth = snapshot.canvasWidth
        guard !snapshot.panels.isEmpty else { throw CompositorError.noPanels }

        let (layouts, totalHeightF) = computeLayout(
            panels: snapshot.panels,
            canvasWidth: canvasWidth
        )
        let totalHeight = Int(ceil(totalHeightF))
        guard totalHeight > 0 else { throw CompositorError.noPanels }
        guard totalHeight <= maxCanvasHeight else {
            throw CompositorError.canvasTooLarge(height: totalHeight)
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: canvasWidth,
            height: totalHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw CompositorError.bitmapContextFailed
        }

        context.setFillColor(cgColor(hex: snapshot.backgroundHex))
        context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: totalHeight))

        // No global CTM flip: `context.draw(image, in:)` renders images right-
        // side-up in CG's native bottom-left coord system, so flipping the
        // whole CTM would invert each panel. Instead, convert each panel's
        // top-down `topY` into a bottom-up destY in `drawPanel`.

        context.interpolationQuality = .high

        let total = Double(layouts.count)
        for (idx, layout) in layouts.enumerated() {
            if Task.isCancelled { throw CompositorError.cancelled }
            try autoreleasepool {
                try drawPanel(
                    layout: layout,
                    into: context,
                    canvasWidth: canvasWidth,
                    canvasHeight: totalHeight
                )
            }
            progress(Double(idx + 1) / total)
        }

        if Task.isCancelled { throw CompositorError.cancelled }

        guard let cgImage = context.makeImage() else {
            throw CompositorError.encodingFailed
        }

        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw CompositorError.encodingFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CompositorError.encodingFailed
        }

        return destinationURL
    }

    // MARK: - Per-panel drawing

    nonisolated private static func drawPanel(
        layout: Layout,
        into context: CGContext,
        canvasWidth: Int,
        canvasHeight: Int
    ) throws {
        let panel = layout.panel

        guard let source = CGImageSourceCreateWithURL(panel.assetURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CompositorError.sourceImageMissing(panel.assetURL)
        }

        let imgW = image.width
        let imgH = image.height

        let srcX = Int((panel.cropX * Double(imgW)).rounded())
        let srcY = Int((panel.cropY * Double(imgH)).rounded())
        let srcW = max(1, Int((panel.cropW * Double(imgW)).rounded()))
        let srcH = max(1, Int((panel.cropH * Double(imgH)).rounded()))
        let clampedW = max(1, min(srcW, imgW - srcX))
        let clampedH = max(1, min(srcH, imgH - srcY))
        let srcRect = CGRect(x: srcX, y: srcY, width: clampedW, height: clampedH)

        guard let cropped = image.cropping(to: srcRect) else {
            throw CompositorError.croppingFailed
        }

        // Convert top-down topY into bottom-up destY for CG's native coords.
        let destY = Double(canvasHeight) - layout.topY - layout.displayHeight
        let destRect = CGRect(
            x: 0,
            y: destY,
            width: Double(canvasWidth),
            height: layout.displayHeight
        )
        context.draw(cropped, in: destRect)
    }

    // MARK: - Hex -> CGColor (kept local so Compositor has no UIKit dependency)

    nonisolated private static func cgColor(hex: String) -> CGColor {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var rgb: UInt64 = 0
        Scanner(string: s).scanHexInt64(&rgb)
        let r: Double
        let g: Double
        let b: Double
        if s.count == 3 {
            r = Double((rgb & 0xF00) >> 8) / 15.0
            g = Double((rgb & 0x0F0) >> 4) / 15.0
            b = Double(rgb & 0x00F) / 15.0
        } else {
            r = Double((rgb & 0xFF0000) >> 16) / 255.0
            g = Double((rgb & 0x00FF00) >> 8) / 255.0
            b = Double(rgb & 0x0000FF) / 255.0
        }
        return CGColor(red: r, green: g, blue: b, alpha: 1)
    }
}
