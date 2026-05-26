import SwiftUI
import SwiftData
import PhotosUI

struct EditorView: View {
    @Bindable var project: Project
    @Environment(\.modelContext) private var modelContext

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importDone = 0
    @State private var importTotal = 0
    @State private var importError: String?
    @State private var showingSettings = false

    private var sortedPanels: [Panel] {
        project.panels.sorted { $0.order < $1.order }
    }

    var body: some View {
        ZStack {
            Color(hex: project.backgroundHex)
                .ignoresSafeArea()

            if sortedPanels.isEmpty {
                emptyState
            } else {
                canvasScroll
            }

            if isImporting {
                importOverlay
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Label("Project Settings", systemImage: "gearshape")
                }

                PhotosPicker(
                    selection: $selectedItems,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Add Panels", systemImage: "plus")
                }
                .disabled(isImporting)
            }
        }
        .sheet(isPresented: $showingSettings) {
            CanvasSettingsSheet(project: project)
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            let items = newItems
            selectedItems = []
            Task { await runImport(items: items) }
        }
        .alert(
            "Couldn't import",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(importError ?? "") }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("No panels yet")
                .font(.title2.bold())
            Text("Tap + in the top right to add panels from your photo library.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private var canvasScroll: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedPanels) { panel in
                    PanelRowView(panel: panel)
                }
            }
        }
    }

    private var importOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Importing \(importDone) of \(importTotal)…")
                .font(.callout)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func runImport(items: [PhotosPickerItem]) async {
        isImporting = true
        importDone = 0
        importTotal = items.count
        defer { isImporting = false }

        let targetWidth = project.canvasWidth
        let panelsDir = ProjectStore.shared.panelsDirectory(for: project)
        var nextOrder = (project.panels.map(\.order).max() ?? -1) + 1

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    continue
                }

                let filename = UUID().uuidString + ".png"
                let destURL = panelsDir.appending(path: filename)

                let dims = try await Task.detached(priority: .userInitiated) {
                    try ImageImporter.importPanel(
                        data: data,
                        targetWidth: targetWidth,
                        destinationURL: destURL
                    )
                }.value

                let panel = Panel(
                    order: nextOrder,
                    assetFilename: filename,
                    width: dims.width,
                    height: dims.height
                )
                panel.project = project
                modelContext.insert(panel)
                nextOrder += 1
                project.updatedAt = Date()
                try? modelContext.save()

                importDone += 1
            } catch {
                importError = error.localizedDescription
                return
            }
        }
    }
}
