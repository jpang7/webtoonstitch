import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID = UUID()
    var name: String = "Untitled Project"
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var canvasWidth: Int = 800
    var backgroundHex: String = "#FFFFFF"

    @Relationship(deleteRule: .cascade, inverse: \Panel.project)
    var panels: [Panel] = []

    init(
        name: String = "Untitled Project",
        canvasWidth: Int = 800,
        backgroundHex: String = "#FFFFFF"
    ) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.canvasWidth = canvasWidth
        self.backgroundHex = backgroundHex
        self.panels = []
    }
}
