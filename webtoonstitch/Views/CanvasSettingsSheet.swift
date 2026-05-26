import SwiftUI
import SwiftData

struct CanvasSettingsSheet: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss

    private var canvasWidthLocked: Bool {
        !project.panels.isEmpty
    }

    private var backgroundBinding: Binding<Color> {
        Binding(
            get: { Color(hex: project.backgroundHex) },
            set: { newColor in
                project.backgroundHex = newColor.hexString
                project.updatedAt = Date()
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Project name", text: $project.name)
                        .textInputAutocapitalization(.words)
                        .onChange(of: project.name) { _, _ in
                            project.updatedAt = Date()
                        }
                }

                Section {
                    if canvasWidthLocked {
                        HStack {
                            Text("Width")
                            Spacer()
                            Text("\(project.canvasWidth) px")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Stepper(value: $project.canvasWidth, in: 200...2000, step: 50) {
                            HStack {
                                Text("Width")
                                Spacer()
                                Text("\(project.canvasWidth) px")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onChange(of: project.canvasWidth) { _, _ in
                            project.updatedAt = Date()
                        }
                    }
                } header: {
                    Text("Canvas")
                } footer: {
                    if canvasWidthLocked {
                        Text("Re-import panels to change canvas width.")
                    } else {
                        Text("Webtoon's canvas spec is 800 px wide.")
                    }
                }

                Section("Background") {
                    ColorPicker(
                        "Color",
                        selection: backgroundBinding,
                        supportsOpacity: false
                    )
                }
            }
            .navigationTitle("Project Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
