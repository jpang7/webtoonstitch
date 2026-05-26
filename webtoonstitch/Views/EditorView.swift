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
    @State private var selectedPanelID: UUID?
    @State private var cropTarget: Panel?
    @State private var showingExport = false

    private var sortedPanels: [Panel] {
        project.panels.sorted { $0.order < $1.order }
    }

    private var selectedPanel: Panel? {
        guard let id = selectedPanelID else { return nil }
        return sortedPanels.first(where: { $0.id == id })
    }

    var body: some View {
        ZStack {
            Color(hex: project.backgroundHex)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { selectedPanelID = nil }

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

                Button {
                    showingExport = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(isImporting || sortedPanels.isEmpty)

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
        .safeAreaInset(edge: .bottom) {
            if let panel = selectedPanel {
                inspector(for: panel)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selectedPanelID)
        .sheet(isPresented: $showingSettings) {
            CanvasSettingsSheet(project: project)
        }
        .fullScreenCover(item: $cropTarget) { panel in
            CropSheet(panel: panel)
        }
        .sheet(isPresented: $showingExport) {
            ExportSheet(project: project)
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
        GeometryReader { geo in
            let displayWidth = geo.size.width
            let canvasToScreen = displayWidth / CGFloat(project.canvasWidth)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sortedPanels.enumerated()), id: \.element.id) { idx, panel in
                        let nextOverlapCanvas = idx + 1 < sortedPanels.count
                            ? sortedPanels[idx + 1].overlapWithPrevious
                            : 0
                        let nextOverlapDisplay = CGFloat(nextOverlapCanvas) * canvasToScreen

                        PanelRowView(
                            panel: panel,
                            displayWidth: displayWidth,
                            nextOverlapPx: nextOverlapDisplay,
                            isSelected: selectedPanelID == panel.id,
                            onTap: { toggleSelection(panel) }
                        )
                    }
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

    @ViewBuilder
    private func inspector(for panel: Panel) -> some View {
        let panels = sortedPanels
        let idx = panels.firstIndex(where: { $0.id == panel.id })
        let canMoveUp = (idx ?? 0) > 0
        let canMoveDown = (idx.map { $0 < panels.count - 1 }) ?? false

        let previousDisplayedHeight: Double = {
            guard let i = idx, i > 0 else { return 0 }
            let prev = panels[i - 1]
            guard prev.width > 0, prev.cropW > 0 else { return 0 }
            let aspect = Double(prev.height) / Double(prev.width)
            return Double(project.canvasWidth) * aspect * prev.cropH / prev.cropW
        }()
        let bound = max(50, previousDisplayedHeight)
        let overlapRange = -bound ... bound

        PanelInspectorView(
            panel: panel,
            canMoveUp: canMoveUp,
            canMoveDown: canMoveDown,
            overlapRange: overlapRange,
            onMoveUp: { move(panel, by: -1) },
            onMoveDown: { move(panel, by: +1) },
            onCrop: { cropTarget = panel },
            onDelete: { delete(panel) }
        )
    }

    // MARK: - Selection

    private func toggleSelection(_ panel: Panel) {
        if selectedPanelID == panel.id {
            selectedPanelID = nil
        } else {
            selectedPanelID = panel.id
        }
    }

    // MARK: - Reorder

    private func move(_ panel: Panel, by delta: Int) {
        var panels = sortedPanels
        guard let idx = panels.firstIndex(where: { $0.id == panel.id }) else { return }
        let newIdx = idx + delta
        guard newIdx >= 0 && newIdx < panels.count else { return }
        panels.swapAt(idx, newIdx)
        for (i, p) in panels.enumerated() { p.order = i }
        project.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Delete

    private func delete(_ panel: Panel) {
        guard let project = panel.project else { return }
        let url = ProjectStore.shared.panelFileURL(
            for: project,
            filename: panel.assetFilename
        )
        try? FileManager.default.removeItem(at: url)
        PanelImageCache.shared.invalidate(panelID: panel.id)
        selectedPanelID = nil
        modelContext.delete(panel)
        project.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Import

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
