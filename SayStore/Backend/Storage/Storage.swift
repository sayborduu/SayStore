//
//  Persistence.swift
//  Feather
//
//  Created by samara on 10.04.2025.
//

import CoreData
import Foundation
import OSLog

// MARK: - Storage
final class Storage: ObservableObject {
	static let shared = Storage()
	let container: NSPersistentContainer
	
	private let _name: String = "SayStore"
	private let _logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SayStore", category: "Storage")

	init(inMemory: Bool = false) {
		container = NSPersistentContainer(name: _name)

		if inMemory {
			container.persistentStoreDescriptions.first?.url =
				URL(fileURLWithPath: "/dev/null")
		}

		_loadPersistentStoreAggressively()
		container.viewContext.automaticallyMergesChangesFromParent = true
		container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
	}

	var context: NSManagedObjectContext {
		container.viewContext
	}
	
	func saveContext() {
		DispatchQueue.main.async {
			if self.context.hasChanges {
				try? self.context.save()
			}
		}
	}
	
	func clearContext<T: NSManagedObject>(request: NSFetchRequest<T>) {
		let deleteRequest = NSBatchDeleteRequest(fetchRequest: (request as? NSFetchRequest<NSFetchRequestResult>)!)
		_ = try? context.execute(deleteRequest)
	}
	
	func countContent<T: NSManagedObject>(for type: T.Type) -> String {
		let request = T.fetchRequest()
		return "\((try? context.count(for: request)) ?? 0)"
	}

	private func _loadPersistentStoreAggressively() {
		container.loadPersistentStores { description, error in
			if error != nil {
				self._logger.error("Core Data store load failed, recreating store: \(String(describing: error), privacy: .public)")
				self._destroyStore(at: description.url)
				self.container.loadPersistentStores { _, retryError in
					if let retryError {
						self._logger.error("Core Data store reload failed, falling back to in-memory store: \(String(describing: retryError), privacy: .public)")
						self.container.persistentStoreDescriptions.forEach { $0.type = NSInMemoryStoreType }
						self.container.loadPersistentStores { _, fallbackError in
							if let fallbackError {
								self._logger.critical("Core Data in-memory fallback failed: \(String(describing: fallbackError), privacy: .public)")
							}
						}
					}
				}
			}
		}
	}

	private func _destroyStore(at url: URL?) {
		guard let url else { return }

		let base = url.deletingPathExtension()
		let fm = FileManager.default

		let files = [
			base.appendingPathExtension("sqlite"),
			base.appendingPathExtension("sqlite-wal"),
			base.appendingPathExtension("sqlite-shm")
		]

		for file in files {
			try? fm.removeItem(at: file)
		}
		
		try? FileManager.default.removeFileIfNeeded(at: FileManager.default.signed)
		try? FileManager.default.removeFileIfNeeded(at: FileManager.default.unsigned)
		try? FileManager.default.removeFileIfNeeded(at: FileManager.default.certificates)
		UserDefaults.standard.set(0, forKey: "SayStore.selectedCert")
	}
}
