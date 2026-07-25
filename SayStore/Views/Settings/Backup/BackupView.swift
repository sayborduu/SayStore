import SwiftUI
import NimbleViews

struct BackupView: View {
    @StateObject private var backupManager = BackupManager.shared
    @State private var isCreating = false
    @State private var selectedBackup: Backup?
    @State private var showDeleteConfirm: Backup?

    var body: some View {
        NBList("Backup") {
            Section {
                Button {
                    isCreating = true
                } label: {
                    Label("Create New Backup", systemImage: "plus.square")
                }
            }

            if backupManager.backups.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        ContentUnavailableView {
                            Label("No Backups", systemImage: "internaldrive")
                        } description: {
                            Text("Create a backup to save your apps, certificates, and settings.")
                        }
                    }
                }
            } else {
                NBSection("Backups", secondary: backupManager.backups.count.description) {
                    ForEach(backupManager.backups) { backup in
                        NavigationLink(destination: BackupDetailView(backup: backup)) {
                            _row(for: backup)
                        }
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                showDeleteConfirm = backup
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            BackupCreateView()
        }
        .alert("Delete Backup", isPresented: Binding(
            get: { showDeleteConfirm != nil },
            set: { if !$0 { showDeleteConfirm = nil } }
        )) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let backup = showDeleteConfirm {
                    backupManager.deleteBackup(backup)
                }
                showDeleteConfirm = nil
            }
        } message: {
            if let backup = showDeleteConfirm {
                Text("Are you sure you want to delete \"\(backup.name)\"? This cannot be undone.")
            }
        }
    }

    @ViewBuilder
    private func _row(for backup: Backup) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "internaldrive")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(backup.name)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(backup.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ByteCountFormatter.string(fromByteCount: backup.fileSize, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "app.badge")
                    .font(.caption2)
                Text("\(backup.appCount)")
                    .font(.caption.bold())
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .quaternarySystemFill))
            .clipShape(Capsule())
        }
        .padding(.vertical, 4)
    }
}
