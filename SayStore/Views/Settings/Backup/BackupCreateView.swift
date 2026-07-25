import SwiftUI
import NimbleViews

struct BackupCreateView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var backupManager = BackupManager.shared

    @FetchRequest(
        entity: Signed.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
        animation: .snappy
    ) private var signedApps: FetchedResults<Signed>

    @FetchRequest(
        entity: Imported.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
        animation: .snappy
    ) private var importedApps: FetchedResults<Imported>

    @FetchRequest(
        entity: CertificatePair.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \CertificatePair.date, ascending: false)],
        animation: .snappy
    ) private var certificates: FetchedResults<CertificatePair>

    @FetchRequest(
        entity: AltSource.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.date, ascending: false)],
        animation: .snappy
    ) private var sources: FetchedResults<AltSource>

    @State private var signedItems: [BackupAppItem] = []
    @State private var importedItems: [BackupAppItem] = []
    @State private var certItems: [BackupCertificateItem] = []
    @State private var sourceItems: [BackupSourceItem] = []
    @State private var includeSettings = true
    @State private var includeArchives = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var selectedCount: Int {
        let s = signedItems.filter(\.isSelected).count
        let i = importedItems.filter(\.isSelected).count
        return s + i
    }

    private var canCreate: Bool {
        selectedCount > 0 || certItems.contains(where: \.isSelected) || sourceItems.contains(where: \.isSelected)
    }

    var body: some View {
        NBNavigationView("Create Backup", displayMode: .inline) {
            Form {
                if !signedItems.isEmpty {
                    NBSection("Signed Apps", secondary: signedItems.filter(\.isSelected).count.description) {
                        Button("Select All / None") {
                            let allSelected = signedItems.allSatisfy(\.isSelected)
                            for i in signedItems.indices {
                                signedItems[i].isSelected = !allSelected
                            }
                        }
                        .font(.caption)
                        ForEach($signedItems) { $item in
                            _appRow(item: $item)
                        }
                    }
                }

                if !importedItems.isEmpty {
                    NBSection("Imported Apps", secondary: importedItems.filter(\.isSelected).count.description) {
                        Button("Select All / None") {
                            let allSelected = importedItems.allSatisfy(\.isSelected)
                            for i in importedItems.indices {
                                importedItems[i].isSelected = !allSelected
                            }
                        }
                        .font(.caption)
                        ForEach($importedItems) { $item in
                            _appRow(item: $item)
                        }
                    }
                }

                if !certItems.isEmpty {
                    NBSection("Certificates", secondary: certItems.filter(\.isSelected).count.description) {
                        Button("Select All / None") {
                            let allSelected = certItems.allSatisfy(\.isSelected)
                            for i in certItems.indices {
                                certItems[i].isSelected = !allSelected
                            }
                        }
                        .font(.caption)
                        ForEach($certItems) { $item in
                            HStack {
                                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isSelected ? .accentColor : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.nickname ?? item.appIDName ?? "Unknown")
                                        .font(.body)
                                    if let expiration = item.expiration {
                                        Text(expiration.formatted(date: .abbreviated, time: .omitted))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                item.isSelected.toggle()
                            }
                        }
                    }
                }

                if !sourceItems.isEmpty {
                    NBSection("Sources", secondary: sourceItems.filter(\.isSelected).count.description) {
                        Button("Select All / None") {
                            let allSelected = sourceItems.allSatisfy(\.isSelected)
                            for i in sourceItems.indices {
                                sourceItems[i].isSelected = !allSelected
                            }
                        }
                        .font(.caption)
                        ForEach($sourceItems) { $item in
                            HStack {
                                Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isSelected ? .accentColor : .secondary)
                                    .font(.title3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name ?? "Unknown")
                                        .font(.body)
                                    if let url = item.sourceURL {
                                        Text(url)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                item.isSelected.toggle()
                            }
                        }
                    }
                }

                NBSection("Options") {
                    Toggle("Save App Settings", systemImage: "gearshape", isOn: $includeSettings)
                    Toggle("Include Archives", systemImage: "archivebox", isOn: $includeArchives)
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
                        _create()
                    } label: {
                        HStack {
                            Spacer()
                            if isCreating {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Create Backup")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canCreate || isCreating)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(canCreate && !isCreating ? Color.accentColor : Color.gray.opacity(0.3))
                    )
                    .foregroundStyle(.white)
                }
            }
            .toolbar {
                NBToolbarButton(role: .close)
            }
            .disabled(isCreating)
        }
        .task(id: signedApps.count) {
            signedItems = signedApps.map(BackupAppItem.init)
        }
        .task(id: importedApps.count) {
            importedItems = importedApps.map(BackupAppItem.init)
        }
        .task(id: certificates.count) {
            certItems = certificates.map(BackupCertificateItem.init)
        }
        .task(id: sources.count) {
            sourceItems = sources.map(BackupSourceItem.init)
        }
    }

    @ViewBuilder
    private func _appRow(item: Binding<BackupAppItem>) -> some View {
        let app = item.wrappedValue
        HStack(spacing: 12) {
            Image(systemName: app.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(app.isSelected ? .accentColor : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .font(.body)
                Text("\(app.version) • \(app.identifier)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if app.isSelected {
                if app.canUseURLOnly {
                    Picker("", selection: item.storageMode) {
                        ForEach(BackupStorageMode.allCases, id: \.rawValue) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                } else {
                    Text("Full App")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            item.wrappedValue.isSelected.toggle()
        }
    }

    private func _create() {
        isCreating = true
        errorMessage = nil
        let name = "Backup - \(Date().formatted(date: .abbreviated, time: .shortened))"

        Task {
            do {
                _ = try await backupManager.createBackup(
                    name: name,
                    signedApps: signedItems,
                    importedApps: importedItems,
                    certificates: certItems,
                    sources: sourceItems,
                    includeSettings: includeSettings,
                    includeArchives: includeArchives
                )
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}
