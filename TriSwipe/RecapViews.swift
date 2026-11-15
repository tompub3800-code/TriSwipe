import SwiftUI

/// Écran affiché juste après avoir vidé la corbeille.
@MainActor
struct RecapView: View {
    let record: CleanupRecord
    let onClose: () -> Void
    @Environment(SortStore.self) private var store

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
            Text("\(formatBytes(record.bytes)) libérés")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            HStack(spacing: 0) {
                tile("\(record.count)", "supprimés")
                tile("\(record.count - record.videos)", "photos")
                tile("\(record.videos)", "vidéos")
            }
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 24)

            Text("Au total depuis le début : \(formatBytes(store.stats.bytesFreed)) libérés, \(store.stats.deleted) éléments supprimés.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Text("Ils restent 30 jours dans « Supprimés récemment » de l'app Photos.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(action: onClose) {
                Text("Continuer").bold().frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom)
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Historique de tous les nettoyages.
@MainActor
struct HistoryView: View {
    @Environment(SortStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateStyle = .long
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Espace libéré", value: formatBytes(store.stats.bytesFreed))
                    LabeledContent("Éléments supprimés", value: "\(store.stats.deleted)")
                    LabeledContent("Gardés", value: "\(store.stats.kept)")
                    LabeledContent("Rangés dans un album", value: "\(store.stats.albumed)")
                } header: {
                    Text("Depuis le début")
                }

                Section("Nettoyages") {
                    if store.cleanups.isEmpty {
                        Text("Aucun nettoyage pour l'instant.").foregroundStyle(.secondary)
                    }
                    ForEach(store.cleanups) { c in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Self.formatter.string(from: c.date)).font(.subheadline.weight(.semibold))
                            Text("\(c.count) supprimés (\(c.videos) vidéos) · \(formatBytes(c.bytes))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Récap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
