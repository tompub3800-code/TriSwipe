import SwiftUI

@MainActor
struct HomeView: View {
    @Environment(SortStore.self) private var store
    @State private var showTrash = false
    @State private var showReset = false
    @State private var showHistory = false
    @State private var showAlbumSource = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            List {
                Section {
                    Button { showHistory = true } label: { statsCard }
                        .buttonStyle(.plain)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if let m = store.resumeMonth {
                    Section {
                        Button {
                            store.start(.month(year: m.year, month: m.month), title: m.title)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "play.circle.fill").font(.title2)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Reprendre où j'en étais").font(.headline)
                                        Text("\(m.title) · encore \(m.remaining) à trier")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(m.progress * 100)) %").font(.headline).monospacedDigit()
                                }
                                ProgressView(value: m.progress)
                            }
                            .padding(.vertical, 4)
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Afficher") {
                    Picker("Type", selection: $store.mediaFilter) {
                        ForEach(MediaFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Picker("Ordre", selection: $store.order) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Tri rapide") {
                    quickRow(.all, title: "Tout ce qui n'est pas trié", icon: "photo.stack", color: .accentColor)
                    quickRow(.onThisDay, title: "Ce jour-là", icon: "calendar", color: .orange)
                    quickRow(.screenshots, title: "Captures d'écran", icon: "camera.viewfinder", color: .purple)
                    quickRow(.longVideos, title: "Vidéos les plus longues", icon: "film.stack", color: .red)
                    Button {
                        showAlbumSource = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Text("Trier un album…").foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("Par mois") {
                    ForEach(store.months) { month in
                        monthRow(month)
                    }
                }
            }
            .navigationTitle("TriSwipe")
            .overlay {
                if store.isLoading {
                    ProgressView("Lecture de la photothèque…")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .refreshable { await store.load() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Récap des nettoyages", systemImage: "chart.bar") {
                            showHistory = true
                        }
                        Button("Actualiser", systemImage: "arrow.clockwise") {
                            Task { await store.load() }
                        }
                        Button("Remettre à zéro la progression", systemImage: "arrow.counterclockwise", role: .destructive) {
                            showReset = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showTrash = true
                    } label: {
                        Image(systemName: store.trashCount > 0 ? "trash.fill" : "trash")
                            .overlay(alignment: .topTrailing) {
                                if store.trashCount > 0 {
                                    Text("\(store.trashCount)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .background(.red, in: Capsule())
                                        .offset(x: 10, y: -8)
                                }
                            }
                    }
                }
            }
            .sheet(isPresented: $showTrash) { TrashView() }
            .sheet(isPresented: $showHistory) { HistoryView() }
            .sheet(isPresented: $showAlbumSource) {
                AlbumPickerView(title: "Trier un album", allowCreate: false) { id in
                    showAlbumSource = false
                    let name = store.albums.first { $0.id == id }?.title ?? "Album"
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        store.start(.album(id), title: name)
                    }
                }
            }
            .confirmationDialog("Remettre à zéro ?", isPresented: $showReset, titleVisibility: .visible) {
                Button("Tout remettre à trier", role: .destructive) { store.resetProgress() }
            } message: {
                Text("Toutes tes photos réapparaîtront comme « à trier ». Rien n'est supprimé.")
            }
            .alert("Oups", isPresented: Binding(
                get: { store.errorMessage != nil && store.session == nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK") { store.errorMessage = nil }
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { store.session != nil },
            set: { if !$0 { store.endSession() } }
        )) {
            SwipeView()
        }
    }

    // MARK: Statistiques

    private var statsCard: some View {
        HStack(spacing: 0) {
            stat(value: formatBytes(store.stats.bytesFreed), label: "libérés", icon: "sparkles")
            Divider().frame(height: 40)
            stat(value: "\(store.stats.sorted)", label: "triées", icon: "checkmark.circle")
            Divider().frame(height: 40)
            stat(value: "\(store.trashCount)", label: "en corbeille", icon: "trash")
        }
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func stat(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Lignes

    private func quickRow(_ source: SortSource, title: String, icon: String, color: Color) -> some View {
        let count = store.quickCounts[source] ?? 0
        return Button {
            store.start(source, title: title)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
            }
        }
        .disabled(count == 0)
    }

    private func monthRow(_ month: MonthGroup) -> some View {
        Button {
            store.start(.month(year: month.year, month: month.month), title: month.title)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(month.title).foregroundStyle(.primary)
                    Spacer()
                    if month.remaining == 0 {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Text("\(Int(month.progress * 100)) % · \(month.remaining) à trier")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                ProgressView(value: month.progress)
                    .tint(month.remaining == 0 ? .green : .accentColor)
                if store.deleted(in: month) > 0 {
                    Text("\(store.deleted(in: month)) supprimés · \(formatBytes(store.bytesFreed(in: month))) libérés")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(month.remaining == 0)
    }
}
