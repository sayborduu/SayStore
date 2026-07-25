import SwiftUI
import NimbleViews

struct BackupDetailView: View {
    let backup: Backup
    @StateObject private var backupManager = BackupManager.shared
    @State private var contents: BackupContents?
    @State private var isLoadingContents = true
    @State private var isRestoring = false
    @State private var restoreResult: RestoreResult?
    @State private var showRestoreConfirm = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NBList(backup.name) {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "internaldrive")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(backup.name)
                        .font(.title2).fontWeight(.semibold)
                    HStack(spacing: 8) {
                        Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                        Text(ByteCountFormatter.string(fromByteCount: backup.fileSize, countStyle: .file))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(EmptyView())
            }

            if isLoadingContents {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading contents...")
                        Spacer()
                    }
                }
            } else if let contents {
                if !contents.apps.isEmpty {
                    NBSection("Apps", secondary: contents.apps.count.description) {
                        ForEach(contents.apps) { app in
                            HStack(spacing: 12) {
                                Image(systemName: app.isSigned ? "checkmark.seal" : "arrow.down.doc")
                                    .font(.title3)
                                    .foregroundStyle(app.isSigned ? .blue : .orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.body)
                                    Text("\(app.version) • \(app.identifier)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                HStack(spacing: 4) {
                                    if app.storageMode == .urlOnly {
                                        Image(systemName: "link")
                                            .font(.caption2)
                                        Text("URL")
                                    } else {
                                        Image(systemName: "app.fill")
                                            .font(.caption2)
                                        Text("Full")
                                    }
                                }
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color(uiColor: .quaternarySystemFill))
                                .clipShape(Capsule())
                            }
                        }
                    }
                }

                if !contents.certificates.isEmpty {
                    NBSection("Certificates", secondary: contents.certificates.count.description) {
                        ForEach(contents.certificates) { cert in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(cert.nickname ?? cert.appIDName ?? "Unknown")
                                    .font(.body)
                                if let expiration = cert.expiration {
                                    Text(expiration.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if !contents.sources.isEmpty {
                    NBSection("Sources", secondary: contents.sources.count.description) {
                        ForEach(contents.sources) { source in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(source.name ?? "Unknown")
                                    .font(.body)
                                if let url = source.sourceURL {
                                    Text(url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                Section {
                    if contents.includesSettings {
                        Label("Settings included", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    if contents.includesArchives {
                        Label("Archives included", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                if let result = restoreResult {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Restore Complete")
                                .font(.headline)
                                .foregroundStyle(.green)
                            Text("\(result.appsRestored) apps restored, \(result.certificatesRestored) certificates restored")
                            Text("\(result.sourcesAdded) sources added, \(result.settingsRestored ? "settings restored" : "")")
                            if result.appsSkipped > 0 {
                                Text("\(result.appsSkipped) apps already existed (skipped)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button {
                        showRestoreConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            if isRestoring {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Label("Restore", systemImage: "arrow.counterclockwise")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isRestoring)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isRestoring ? Color.gray.opacity(0.3) : Color.accentColor)
                    )
                    .foregroundStyle(.white)

                    Button {
                        _share()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Share", systemImage: "square.and.arrow.up")
                            Spacer()
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Backup", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
        }
        .task {
            await loadContents()
        }
        .alert("Restore Backup", isPresented: $showRestoreConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                _restore()
            }
        } message: {
            Text("This will restore all apps, certificates, and settings from this backup. Existing data with the same identifiers will be updated.")
        }
        .alert("Delete Backup", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                backupManager.deleteBackup(backup)
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete this backup? This cannot be undone.")
        }
    }

    @MainActor
    private func loadContents() {
        isLoadingContents = true
        Task {
            let c = backupManager.readContents(for: backup)
            contents = c
            isLoadingContents = false
        }
    }

    private func _restore() {
        isRestoring = true
        errorMessage = nil
        Task {
            do {
                let result = try await backupManager.restoreBackup(backup)
                await MainActor.run {
                    restoreResult = result
                    isRestoring = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isRestoring = false
                }
            }
        }
    }

    private func _share() {
        let url = backupManager.backupFileURL(for: backup)
        let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }
}
