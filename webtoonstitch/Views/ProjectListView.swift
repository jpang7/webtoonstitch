import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    @State private var showingNewProject = false
    @State private var renamingProject: Project?
    @State private var renameText: String = ""

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
            .navigationTitle("Webtoon Stitch")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewProject = true
                    } label: {
                        Label("New Project", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewProject) {
                NewProjectSheet()
            }
            .alert(
                "Rename Project",
                isPresented: Binding(
                    get: { renamingProject != nil },
                    set: { if !$0 { renamingProject = nil } }
                )
            ) {
                TextField("Project name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    renamingProject = nil
                }
                Button("Save") {
                    commitRename()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No projects yet")
                .font(.title2.bold())
            Text("Tap + to create your first project.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(projects) { project in
                    NavigationLink {
                        EditorView(project: project)
                    } label: {
                        ProjectCard(project: project)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            renameText = project.name
                            renamingProject = project
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            delete(project)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    private func commitRename() {
        guard let project = renamingProject else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            project.name = trimmed
            project.updatedAt = Date()
            try? modelContext.save()
        }
        renamingProject = nil
    }

    private func delete(_ project: Project) {
        try? ProjectStore.shared.deleteProjectDirectory(for: project)
        modelContext.delete(project)
        try? modelContext.save()
    }
}

private struct ProjectCard: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: project.backgroundHex))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.primary.opacity(0.1))
                if project.panels.isEmpty {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(metaLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var metaLine: String {
        let count = project.panels.count
        let panelWord = count == 1 ? "panel" : "panels"
        return "\(count) \(panelWord) · \(project.canvasWidth) px"
    }
}
