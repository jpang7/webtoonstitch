import Foundation

enum ProjectStoreError: LocalizedError {
    case directoryCreationFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let url, let err):
            return "Couldn't create \(url.lastPathComponent): \(err.localizedDescription)"
        }
    }
}

struct ProjectStore {
    static let shared = ProjectStore()

    private let fileManager = FileManager.default

    var documentsRoot: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    var projectsRoot: URL {
        documentsRoot.appending(path: "Projects", directoryHint: .isDirectory)
    }

    func projectDirectory(for project: Project) -> URL {
        projectsRoot.appending(path: project.id.uuidString, directoryHint: .isDirectory)
    }

    func panelsDirectory(for project: Project) -> URL {
        projectDirectory(for: project).appending(path: "panels", directoryHint: .isDirectory)
    }

    @discardableResult
    func createProjectDirectory(for project: Project) throws -> URL {
        let panels = panelsDirectory(for: project)
        do {
            try fileManager.createDirectory(at: panels, withIntermediateDirectories: true)
        } catch {
            throw ProjectStoreError.directoryCreationFailed(panels, underlying: error)
        }
        return projectDirectory(for: project)
    }

    func deleteProjectDirectory(for project: Project) throws {
        let dir = projectDirectory(for: project)
        guard fileManager.fileExists(atPath: dir.path) else { return }
        try fileManager.removeItem(at: dir)
    }

    func panelFileURL(for project: Project, filename: String) -> URL {
        panelsDirectory(for: project).appending(path: filename)
    }
}
