import SwiftUI
import UIKit
import Photos

// MARK: - Controller

@MainActor
@Observable
final class ExportController {
    enum Phase: Equatable {
        case running(progress: Double)
        case completed(url: URL)
        case failed(message: String)
    }

    var phase: Phase = .running(progress: 0)
    private var task: Task<Void, Never>?
    private var consumerTask: Task<Void, Never>?

    func start(snapshot: ProjectSnapshot, destinationURL: URL) {
        cancel()
        phase = .running(progress: 0)

        // Progress stream: the detached exporter yields Doubles; this MainActor
        // task consumes them and updates `phase`. Decouples the @Sendable
        // progress callback from any reference to `self`.
        let (stream, continuation) = AsyncStream.makeStream(of: Double.self)

        consumerTask = Task { [weak self] in
            for await p in stream {
                guard let self else { continue }
                if case .running = phase {
                    phase = .running(progress: p)
                }
            }
        }

        task = Task { [weak self] in
            do {
                let url = try await Self.runExport(
                    snapshot: snapshot,
                    destinationURL: destinationURL,
                    continuation: continuation
                )
                continuation.finish()
                self?.phase = .completed(url: url)
            } catch is CancellationError {
                continuation.finish()
                self?.phase = .failed(message: "Export cancelled.")
            } catch let error as CompositorError {
                continuation.finish()
                self?.phase = .failed(
                    message: error.errorDescription ?? "Unknown error."
                )
            } catch {
                continuation.finish()
                self?.phase = .failed(message: error.localizedDescription)
            }
        }
    }

    nonisolated private static func runExport(
        snapshot: ProjectSnapshot,
        destinationURL: URL,
        continuation: AsyncStream<Double>.Continuation
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try Compositor.export(
                snapshot: snapshot,
                destinationURL: destinationURL,
                progress: { p in continuation.yield(p) }
            )
        }.value
    }

    func cancel() {
        task?.cancel()
        task = nil
        consumerTask?.cancel()
        consumerTask = nil
    }
}

// MARK: - Sheet

struct ExportSheet: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var controller = ExportController()
    @State private var showShare = false
    @State private var saveState: SaveState = .idle

    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(message: String)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                content
                Spacer()
            }
            .padding(24)
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        controller.cancel()
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(isRunning)
        .onAppear { start() }
        .onDisappear { controller.cancel() }
        .sheet(isPresented: $showShare) {
            if case let .completed(url) = controller.phase {
                ShareSheet(items: [url])
            }
        }
    }

    private var isRunning: Bool {
        if case .running = controller.phase { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch controller.phase {
        case .running(let p):
            runningView(progress: p)
        case .completed(let url):
            completedView(url: url)
        case .failed(let msg):
            failedView(message: msg)
        }
    }

    private func runningView(progress: Double) -> some View {
        VStack(spacing: 16) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
            Text(String(format: "Rendering… %d%%", Int(progress * 100)))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private func completedView(url: URL) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            Text("Export complete")
                .font(.title2.bold())
            Text(url.lastPathComponent)
                .foregroundStyle(.secondary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Button {
                Task { await saveToPhotos(url: url) }
            } label: {
                saveToPhotosLabel
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(saveState == .saving || saveState == .saved)

            Button {
                showShare = true
            } label: {
                Label("AirDrop / Share…", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            if case let .failed(msg) = saveState {
                Text(msg)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }

    @ViewBuilder
    private var saveToPhotosLabel: some View {
        switch saveState {
        case .idle, .failed:
            Label("Save to Photos", systemImage: "photo.badge.arrow.down")
        case .saving:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Saving…")
            }
        case .saved:
            Label("Saved to Photos", systemImage: "checkmark")
        }
    }

    private func saveToPhotos(url: URL) async {
        saveState = .saving
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            saveState = .failed(message: "Photos access denied. Enable in Settings → Privacy → Photos → Webtoonstitch.")
            return
        }
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: url, options: nil)
                } completionHandler: { success, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if success {
                        cont.resume()
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "ExportSheet",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Couldn't save to Photos."]
                        ))
                    }
                }
            }
            saveState = .saved
        } catch {
            saveState = .failed(message: error.localizedDescription)
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Export failed")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try Again", action: start)
                .buttonStyle(.bordered)
        }
    }

    private func start() {
        let snapshot = ProjectSnapshot(project: project)
        let url = exportFileURL(name: project.name)
        saveState = .idle
        controller.start(snapshot: snapshot, destinationURL: url)
    }

    private func exportFileURL(name: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let safeName = name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        let filename = "\(safeName)-\(timestamp).png"
        return FileManager.default.temporaryDirectory.appending(path: filename)
    }
}

// MARK: - UIActivityViewController bridge

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
