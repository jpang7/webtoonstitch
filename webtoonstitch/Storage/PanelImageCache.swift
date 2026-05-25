import UIKit

/// In-memory cache of decoded panel images, keyed by panel UUID.
/// `NSCache` is thread-safe and auto-evicts under memory pressure,
/// so this is safe to call from any actor without further locking.
final class PanelImageCache {
    static let shared = PanelImageCache()

    private let cache: NSCache<NSUUID, UIImage> = {
        let c = NSCache<NSUUID, UIImage>()
        c.totalCostLimit = 150 * 1024 * 1024
        return c
    }()

    private init() {}

    func image(forID id: UUID, fileURL: URL) -> UIImage? {
        let key = id as NSUUID
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let img = UIImage(contentsOfFile: fileURL.path) else {
            return nil
        }
        let bytes = img.cgImage.map { $0.width * $0.height * 4 } ?? 0
        cache.setObject(img, forKey: key, cost: bytes)
        return img
    }

    func invalidate(panelID: UUID) {
        cache.removeObject(forKey: panelID as NSUUID)
    }

    func clear() {
        cache.removeAllObjects()
    }
}
