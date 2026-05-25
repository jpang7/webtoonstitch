import Foundation
import SwiftData

@Model
final class Panel {
    var id: UUID = UUID()
    var project: Project?
    var order: Int = 0
    var assetFilename: String = ""
    var width: Int = 0
    var height: Int = 0

    var cropX: Double = 0
    var cropY: Double = 0
    var cropW: Double = 1
    var cropH: Double = 1

    var overlapWithPrevious: Double = 0

    init(
        order: Int,
        assetFilename: String,
        width: Int,
        height: Int
    ) {
        self.id = UUID()
        self.order = order
        self.assetFilename = assetFilename
        self.width = width
        self.height = height
        self.cropX = 0
        self.cropY = 0
        self.cropW = 1
        self.cropH = 1
        self.overlapWithPrevious = 0
    }
}
