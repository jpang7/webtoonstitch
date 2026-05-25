import SwiftUI
import SwiftData

struct NewProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String = ""
    @State private var canvasWidth: Int = 800
    @State private var backgroundColor: Color = .white
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Untitled Project", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    Stepper(value: $canvasWidth, in: 200...2000, step: 50) {
                        HStack {
                            Text("Width")
                            Spacer()
                            Text("\(canvasWidth) px")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Canvas")
                } footer: {
                    Text("Webtoon's canvas spec is 800 px wide.")
                }

                Section("Background") {
                    ColorPicker("Color", selection: $backgroundColor, supportsOpacity: false)
                }
            }
            .navigationTitle("New Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                }
            }
            .alert(
                "Couldn't create project",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(errorMessage ?? "") }
            )
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "Untitled Project" : trimmed

        let project = Project(
            name: finalName,
            canvasWidth: canvasWidth,
            backgroundHex: backgroundColor.hexString
        )
        modelContext.insert(project)

        do {
            try ProjectStore.shared.createProjectDirectory(for: project)
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.delete(project)
            errorMessage = error.localizedDescription
        }
    }
}
