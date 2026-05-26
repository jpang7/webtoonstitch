import SwiftUI

struct PanelInspectorView: View {
    @Bindable var panel: Panel
    let canMoveUp: Bool
    let canMoveDown: Bool
    let overlapRange: ClosedRange<Double>
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onCrop: () -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                Button(action: onMoveUp) {
                    Label("Up", systemImage: "arrow.up")
                        .labelStyle(.iconOnly)
                }
                .disabled(!canMoveUp)

                Button(action: onMoveDown) {
                    Label("Down", systemImage: "arrow.down")
                        .labelStyle(.iconOnly)
                }
                .disabled(!canMoveDown)

                Button(action: onCrop) {
                    Label("Crop", systemImage: "crop")
                        .labelStyle(.iconOnly)
                }

                Spacer()

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
            }
            .font(.title3)
            .buttonStyle(.bordered)

            if canMoveUp {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Overlap above")
                            .font(.callout)
                        Spacer()
                        Text(overlapLabel)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(
                        value: $panel.overlapWithPrevious,
                        in: overlapRange,
                        step: 1
                    )
                }
            } else {
                Text("First panel — overlap not applicable.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .confirmationDialog(
            "Delete panel?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the panel from the project and deletes its image file.")
        }
    }

    private var overlapLabel: String {
        let v = Int(panel.overlapWithPrevious.rounded())
        if v > 0 {
            return "+\(v) px overlap"
        } else if v < 0 {
            return "\(v) px gap"
        } else {
            return "0 px"
        }
    }
}
