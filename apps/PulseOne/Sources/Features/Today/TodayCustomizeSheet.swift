import PulseCore
import SwiftUI

/// "Heute anpassen": show or hide each tile and drag to reorder. Stored per iPhone.
struct TodayCustomizeSheet: View {
    @Binding var layoutData: Data
    @Environment(\.dismiss) private var dismiss

    private var layout: TodayLayout { TodayLayout.decode(layoutData.isEmpty ? nil : layoutData) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(layout.order) { tile in
                        Toggle(isOn: binding(for: tile)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tile.title)
                                    .font(Typography.body)
                                    .foregroundStyle(Palette.ink)
                                if let note = Self.note(for: tile) {
                                    Text(note)
                                        .font(Typography.caption)
                                        .foregroundStyle(Palette.inkMuted)
                                }
                            }
                        }
                        .tint(Palette.bioCyan)
                        .accessibilityIdentifier("customize.\(tile.id)")
                    }
                    .onMove { source, destination in
                        update { $0.move(fromOffsets: source, toOffset: destination) }
                    }
                } footer: {
                    Text("Zum Umsortieren eine Zeile am Griff rechts ziehen. Werte erscheinen nur, wenn eine Quelle sie liefert.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.inkMuted)
                }
                Section {
                    Button("Standard wiederherstellen") { layoutData = TodayLayout.standard.encoded() }
                        .foregroundStyle(Palette.bioCyan)
                        .accessibilityIdentifier("customize.reset")
                }
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Heute anpassen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                        .accessibilityIdentifier("customize.done")
                }
            }
        }
    }

    private func binding(for tile: TodayTile) -> Binding<Bool> {
        Binding(get: { layout.isVisible(tile) },
                set: { visible in update { $0.setVisible(tile, visible) } })
    }

    private func update(_ change: (inout TodayLayout) -> Void) {
        var next = layout
        change(&next)
        layoutData = next.encoded()
    }

    static func note(for tile: TodayTile) -> String? {
        switch tile {
        case .metric(.ringStress): "Herstellerwert des Rings, ohne Bewertung"
        case .metric(.ringHRV): "vom Ring, getrennt von der HRV aus Apple Health"
        case .appleHealth: "nur sichtbar, solange Apple Health nicht verbunden ist"
        default: nil
        }
    }
}
