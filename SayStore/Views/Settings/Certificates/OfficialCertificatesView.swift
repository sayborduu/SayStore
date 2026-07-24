//
//  OfficialCertificatesView.swift
//  SayStore
//
//  Created by NovaDev404 on 07.03.2026.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct OfficialCertificatesView: View {
	@Environment(\.dismiss) private var dismiss

	@State private var _catalogSections: [NovaCerts.CatalogSection] = []
	@State private var _expandedGroups: Set<String> = []
	@State private var _errorMessage: String?
	@State private var _hasLoaded = false
	@State private var _isImporting = false
	@State private var _isLoading = false
	@State private var _importingCertificateID: String?
	@State private var _searchText = ""
	@State private var _selectedFilter: CertificateFilter = .all

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Official Certificates"), displayMode: .inline) {
			_content
		}
		.searchable(text: $_searchText, placement: .platform())
		.animation(.default, value: _filteredCatalogSections.count)
		.animation(.default, value: _isLoading)
		.toolbar {
			_toolbarContent
		}
		.task {
			guard !_hasLoaded else { return }
			await _loadCatalog()
		}
	}

	@ViewBuilder
	private var _content: some View {
		if _isLoading || !_hasLoaded {
			_loadingView
		} else if let errorMessage = _errorMessage {
			_errorView(message: errorMessage)
		} else {
			_catalogList
		}
	}

	@ToolbarContentBuilder
	private var _toolbarContent: some ToolbarContent {
		NBToolbarButton(role: .cancel)

		Menu {
			ForEach(CertificateFilter.allCases, id: \.self) { filter in
				Button {
					_selectedFilter = filter
				} label: {
					HStack {
						Text(filter.title)
						if filter == _selectedFilter {
							Image(systemName: "checkmark")
						}
					}
				}
			}
		} label: {
			Image(systemName: "line.3.horizontal.decrease.circle")
		}

		if _isImporting {
			ToolbarItem(placement: .confirmationAction) {
				ProgressView()
			}
		}
	}
}

// MARK: - Content
extension OfficialCertificatesView {
	private var _catalogList: some View {
		List {
			Section {
				ForEach(_filteredCatalogSections) { section in
					if section.isGroup {
						_groupRow(section)
					} else if let certificate = section.certificates.first {
						_certificateButton(certificate)
					}
				}
			} footer: {
				Text(.localized("Certificates are fetched from the Sideloading.net (aka NovaCerts) API and imported directly into SayStore."))
			}
		}
		.listStyle(.insetGrouped)
		.disabled(_isImporting)
		.refreshable {
			await _loadCatalog(force: true)
		}
		.overlay {
			if _hasLoaded, _errorMessage == nil, !_isLoading, _filteredCatalogSections.isEmpty {
				VStack(spacing: 10) {
					Image(systemName: "slider.horizontal.3")
						.font(.largeTitle)
						.foregroundStyle(.secondary)

					Text(.localized("No Certificates"))
						.font(.headline)

					Text(.localized("Try a different search or filter."))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.padding()
			}
		}
	}

	private var _loadingView: some View {
		VStack(spacing: 12) {
			ProgressView()
			Text(.localized("Fetching NovaCerts..."))
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}

	private func _errorView(message: String) -> some View {
		VStack(spacing: 14) {
			Image(systemName: "exclamationmark.triangle")
				.font(.largeTitle)
				.foregroundStyle(.orange)

			Text(.localized("Couldn't Load NovaCerts"))
				.font(.headline)

			Text(message)
				.font(.footnote)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)

			Button(.localized("Retry")) {
				Task {
					await _loadCatalog(force: true)
				}
			}
			.buttonStyle(.borderedProminent)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}
}

// MARK: - Rows
extension OfficialCertificatesView {
	@ViewBuilder
	private func _groupRow(_ section: NovaCerts.CatalogSection) -> some View {
		DisclosureGroup(isExpanded: _groupExpansionBinding(for: section.id)) {
			ForEach(section.certificates) { certificate in
				_certificateButton(certificate)
			}
		} label: {
			_rowContent(
				title: section.title,
				subtitle: section.subtitle,
				statusText: section.status.title,
				status: section.status,
				isImporting: false
			)
		}
	}

	@ViewBuilder
	private func _certificateButton(_ certificate: NovaCerts.CatalogItem) -> some View {
		Button {
			Task {
				await _import(certificate)
			}
		} label: {
			_rowContent(
				title: certificate.name,
				subtitle: certificate.subtitle,
				statusText: certificate.status.title,
				status: certificate.status,
				isImporting: _importingCertificateID == certificate.id
			)
		}
		.buttonStyle(.plain)
		.disabled(_isImporting)
	}

	private func _rowContent(
		title: String,
		subtitle: String?,
		statusText: String,
		status: NovaCerts.Status,
		isImporting: Bool
	) -> some View {
		HStack(alignment: .center, spacing: 12) {
			VStack(alignment: .leading, spacing: 4) {
				Text(title)
					.font(.body.weight(.medium))
					.foregroundStyle(.primary)
					.multilineTextAlignment(.leading)

				if let subtitle, !subtitle.isEmpty {
					Text(subtitle)
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.leading)
				}
			}

			Spacer(minLength: 12)

			if isImporting {
				ProgressView()
			} else {
				_statusBadge(text: statusText, status: status)
			}
		}
		.contentShape(Rectangle())
	}

	private func _statusBadge(text: String, status: NovaCerts.Status) -> some View {
		let color = _statusColor(for: status)

		return Text(text)
			.font(.footnote.weight(.semibold))
			.foregroundStyle(color)
			.padding(.horizontal, 10)
			.padding(.vertical, 6)
			.background(color.opacity(0.12), in: Capsule())
	}

	private func _statusColor(for status: NovaCerts.Status) -> Color {
		switch status {
		case .signed:
			return .green
		case .revoked:
			return .red
		case .expired:
			return .orange
		case .unknown:
			return .secondary
		}
	}

}

// MARK: - Filter
extension OfficialCertificatesView {
	private var _filteredCatalogSections: [NovaCerts.CatalogSection] {
		_catalogSections.compactMap { section in
			section.filtered(searchText: _searchText, filter: _selectedFilter)
		}
	}

	fileprivate enum CertificateFilter: String, CaseIterable, Hashable {
		case all
		case signed
		case revoked
		case expired
		case unknown

		var title: String {
			switch self {
			case .all:
				.localized("All")
			case .signed:
				.localized("Signed")
			case .revoked:
				.localized("Revoked")
			case .expired:
				.localized("Expired")
			case .unknown:
				.localized("Unknown")
			}
		}

		func matches(_ status: NovaCerts.Status) -> Bool {
			switch self {
			case .all:
				return true
			case .signed:
				return status == .signed
			case .revoked:
				return status == .revoked
			case .expired:
				return status == .expired
			case .unknown:
				return status == .unknown
			}
		}
	}
}

// MARK: - Filtering Helpers
private extension NovaCerts.CatalogItem {
	func matches(searchText: String, filter: OfficialCertificatesView.CertificateFilter) -> Bool {
		guard filter.matches(status) else { return false }
		guard !searchText.isEmpty else { return true }

		let searchableValues = [
			name,
			subtitle,
			status.title,
			rawStatusText,
			validFrom,
			validTo,
			folderName
		]

		return searchableValues.contains { $0.localizedCaseInsensitiveContains(searchText) }
	}
}

private extension NovaCerts.CatalogSection {
	func filtered(searchText: String, filter: OfficialCertificatesView.CertificateFilter) -> NovaCerts.CatalogSection? {
		let matchingCertificates = certificates.filter { $0.matches(searchText: searchText, filter: filter) }
		guard !matchingCertificates.isEmpty else { return nil }

		if matchingCertificates.count == 1, let certificate = matchingCertificates.first {
			return NovaCerts.CatalogSection(
				id: id,
				title: certificate.name,
				subtitle: certificate.subtitle,
				status: certificate.status,
				certificates: matchingCertificates
			)
		}

		return NovaCerts.CatalogSection(
			id: id,
			title: title,
			subtitle: subtitle,
			status: NovaCerts.Status.aggregate(matchingCertificates.map(\.status)),
			certificates: matchingCertificates
		)
	}
}

// MARK: - Actions
extension OfficialCertificatesView {
	@MainActor
	private func _loadCatalog(force: Bool = false) async {
		if _isLoading && !force {
			return
		}

		_isLoading = true
		_errorMessage = nil

		defer {
			_hasLoaded = true
			_isLoading = false
		}

		do {
			_catalogSections = try await NovaCerts.fetchCatalog()
			_expandedGroups = []
		} catch {
			_catalogSections = []
			_errorMessage = error.localizedDescription
		}
	}

	@MainActor
	private func _import(_ certificate: NovaCerts.CatalogItem) async {
		guard !_isImporting else { return }

		_isImporting = true
		_importingCertificateID = certificate.id

		defer {
			_importingCertificateID = nil
			_isImporting = false
		}

		do {
			try await NovaCerts.importCertificate(certificate)
			dismiss()
		} catch {
			UIAlertController.showAlertWithOk(
				title: .localized("Error"),
				message: error.localizedDescription
			)
		}
	}

	private func _groupExpansionBinding(for id: String) -> Binding<Bool> {
		Binding {
			_expandedGroups.contains(id)
		} set: { isExpanded in
			if isExpanded {
				_expandedGroups.insert(id)
			} else {
				_expandedGroups.remove(id)
			}
		}
	}
}