//
//  NovaCerts.swift
//  SayStore
//
//  Created by NovaDev404 on 07.03.2026.
//

import Foundation

enum NovaCerts {
	static let catalogURL = URL(string: "https://sideloading.net/api/certificates/list/all")!

	struct CatalogItem: Identifiable, Hashable {
		let id: String
		let certId: Int
		let name: String
		let folderName: String
		let certificateType: String
		let status: Status
		let rawStatusText: String
		let validFrom: String
		let validTo: String
		fileprivate let order: Int

		var groupingBaseName: String? {
			guard let range = name.range(of: #"\s+\([^()]+\)$"#, options: .regularExpression) else {
				return nil
			}

			let baseName = String(name[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
			return baseName.isEmpty ? nil : baseName
		}

		var p12URL: URL {
			_assetURL(fileName: "cert.p12")
		}

		var provisionURL: URL {
			_assetURL(fileName: "cert.mobileprovision")
		}

		var passwordURL: URL {
			_assetURL(fileName: "password")
		}

		private func _assetURL(fileName: String) -> URL {
			URL(string: "https://sideloading.net/api/certificates/download/\(certId)/\(fileName)")!
		}

		private func remainingDays() -> Int? {
			guard !validTo.isEmpty else { return nil }

			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.timeZone = TimeZone(secondsFromGMT: 0)
			formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"

			guard let validToDate = formatter.date(from: validTo) else { return nil }

			let currentDate = Date()
			let calendar = Calendar.current
			let components = calendar.dateComponents([.day], from: currentDate, to: validToDate)

			return components.day
		}

		var subtitle: String {
			var components: [String] = []
			if !certificateType.isEmpty {
				components.append(certificateType)
			}
			/*if !validFrom.isEmpty {
				components.append(String.localized("Valid From: %@", arguments: validFrom))
			}*/
			if !validTo.isEmpty {
				components.append(String.localized("Valid To: %@", arguments: validTo))
			}

			if let remainingDays = remainingDays() {
				if remainingDays < 0 {
					components.append(String.localized("Expired"))
				} else if remainingDays == 0 {
					components.append(String.localized("Expires Today"))
				} else if remainingDays == 1 {
					components.append(String.localized("Expires Tomorrow"))
				} else {
					components.append(String.localized("Expires in %lld days", arguments: Int64(remainingDays)))
				}
			}
			return components.joined(separator: " • ")
		}
	}

	private struct CatalogResponseItem: Decodable {
		let name: String
		let status: String
		let validFrom: String
		let validTo: String
		let folderName: String
		let id: Int

		private enum CodingKeys: String, CodingKey {
			case name
			case status
			case validFrom = "valid_from"
			case validTo = "valid_to"
			case folderName = "folder_name"
			case id
		}
	}

	struct CatalogSection: Identifiable, Hashable {
		let id: String
		let title: String
		let subtitle: String?
		let status: Status
		let certificates: [CatalogItem]

		var isGroup: Bool {
			certificates.count > 1
		}
	}

	enum Status: String, Hashable {
		case signed
		case revoked
		case expired
		case unknown

		init(markdownValue: String, validTo: String) {
			let normalizedValue = markdownValue.lowercased()
			if let validToDate = Self._validToDate(from: validTo), validToDate < Date() {
				self = .expired
				return
			}

			if normalizedValue.contains("signed") {
				self = .signed
			} else if normalizedValue.contains("revoked") {
				self = .revoked
			} else {
				self = .unknown
			}
		}

		var title: String {
			switch self {
			case .signed:
				String.localized("Signed")
			case .revoked:
				String.localized("Revoked")
			case .expired:
				String.localized("Expired")
			case .unknown:
				String.localized("Unknown")
			}
		}

		static func aggregate(_ statuses: [Status]) -> Status {
			if statuses.contains(.expired) {
				return .expired
			}

			if statuses.contains(.signed) {
				return .signed
			}

			if statuses.contains(.unknown) {
				return .unknown
			}

			return .revoked
		}

		private static func _validToDate(from string: String) -> Date? {
			guard !string.isEmpty else { return nil }

			let formatter = DateFormatter()
			formatter.locale = Locale(identifier: "en_US_POSIX")
			formatter.timeZone = TimeZone(secondsFromGMT: 0)
			formatter.dateFormat = "MMM d HH:mm:ss yyyy zzz"
			return formatter.date(from: string)
		}
	}

	enum NovaCertsError: LocalizedError {
		case invalidResponse(URL)
		case invalidCatalogData
		case invalidTextData(URL)
		case emptyCatalog
		case invalidPassword

		var errorDescription: String? {
			switch self {
			case .invalidResponse(let url):
				String.localized("Failed to fetch %@.", arguments: url.absoluteString)
			case .invalidCatalogData:
				String.localized("The NovaCerts catalog could not be parsed.")
			case .invalidTextData(let url):
				String.localized("The text response from %@ could not be parsed.", arguments: url.absoluteString)
			case .emptyCatalog:
				String.localized("NovaCerts did not return any certificates.")
			case .invalidPassword:
				String.localized("The downloaded NovaCert certificate password is invalid.")
			}
		}
	}
}

// MARK: - Catalog
extension NovaCerts {
	static func fetchCatalog() async throws -> [CatalogSection] {
		let data = try await _downloadData(from: catalogURL)
		let responseItems: [CatalogResponseItem]
		do {
			responseItems = try JSONDecoder().decode([CatalogResponseItem].self, from: data)
		} catch {
			throw NovaCertsError.invalidCatalogData
		}

		let entries = responseItems.enumerated().map { index, item in
			CatalogItem(
				id: String(item.id),
				certId: item.id,
				name: item.name,
				folderName: item.folderName,
				certificateType: item.folderName == item.name ? "" : item.folderName,
				status: Status(markdownValue: item.status, validTo: item.validTo),
				rawStatusText: item.status,
				validFrom: item.validFrom,
				validTo: item.validTo,
				order: index
			)
		}

		guard !entries.isEmpty else {
			throw NovaCertsError.emptyCatalog
		}

		return _buildSections(from: entries)
	}

	private static func _buildSections(from entries: [CatalogItem]) -> [CatalogSection] {
		var groupedEntries: [String: [CatalogItem]] = [:]

		for entry in entries {
			guard let baseName = entry.groupingBaseName else {
				continue
			}

			groupedEntries[baseName, default: []].append(entry)
		}

		var renderedGroups = Set<String>()
		var sections: [CatalogSection] = []

		for entry in entries {
			if let baseName = entry.groupingBaseName,
			   let bucket = groupedEntries[baseName],
			   bucket.count > 1 {
				guard renderedGroups.insert(baseName).inserted else {
					continue
				}

				let sortedBucket = bucket.sorted { $0.order < $1.order }
				sections.append(
					CatalogSection(
						id: "group-\(baseName)",
						title: baseName,
						subtitle: String.localized("%lld versions available", arguments: Int64(sortedBucket.count)),
						status: Status.aggregate(sortedBucket.map(\.status)),
						certificates: sortedBucket
					)
				)
			} else {
				sections.append(
					CatalogSection(
						id: "single-\(entry.id)",
						title: entry.name,
						subtitle: entry.subtitle,
						status: entry.status,
						certificates: [entry]
					)
				)
			}
		}

		return sections
	}
}

// MARK: - Import
extension NovaCerts {
	static func importCertificate(_ certificate: CatalogItem) async throws {
		let fileManager = FileManager.default
		let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent("NovaCerts_\(UUID().uuidString)", isDirectory: true)

		try fileManager.createDirectoryIfNeeded(at: temporaryDirectory)

		do {
			async let p12Contents = _downloadData(from: certificate.p12URL)
			async let provisionContents = _downloadData(from: certificate.provisionURL)
			async let passwordContents = _downloadText(from: certificate.passwordURL)

			let p12URL = temporaryDirectory.appendingPathComponent("certificate.p12")
			let provisionURL = temporaryDirectory.appendingPathComponent("certificate.mobileprovision")
			let p12Data = try await p12Contents
			let provisionData = try await provisionContents
			let passwordText = try await passwordContents

			try p12Data.write(to: p12URL, options: .atomic)
			try provisionData.write(to: provisionURL, options: .atomic)

			let password = passwordText.trimmingCharacters(in: .whitespacesAndNewlines)

			guard FR.checkPasswordForCertificate(for: p12URL, with: password, using: provisionURL) else {
				throw NovaCertsError.invalidPassword
			}

			try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
				FR.handleCertificateFiles(
					p12URL: p12URL,
					provisionURL: provisionURL,
					p12Password: password,
					certificateName: certificate.name
				) { error in
					try? fileManager.removeFileIfNeeded(at: temporaryDirectory)

					if let error {
						continuation.resume(throwing: error)
					} else {
						continuation.resume(returning: ())
					}
				}
			}
		} catch {
			try? fileManager.removeFileIfNeeded(at: temporaryDirectory)
			throw error
		}
	}
}

// MARK: - Networking
extension NovaCerts {
	private static func _downloadData(from url: URL) async throws -> Data {
		var request = URLRequest(url: url)
		request.timeoutInterval = 30
		request.setValue("SayStore/1.0", forHTTPHeaderField: "User-Agent")

		let (data, response) = try await URLSession.shared.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse, (200 ..< 300).contains(httpResponse.statusCode) else {
			throw NovaCertsError.invalidResponse(url)
		}

		return data
	}

	private static func _downloadText(from url: URL) async throws -> String {
		let data = try await _downloadData(from: url)
		guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else {
			throw NovaCertsError.invalidTextData(url)
		}

		return text
	}
}