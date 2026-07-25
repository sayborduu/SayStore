//
//  BackupView.swift
//  SayStore
//
//  Created by Alex Badi on 25/07/2026.
//

import SwiftUI
import Zip
import NimbleViews

// MARK: - View
struct ArchiveView: View {
	//@AppStorage("SayStore.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	
	// MARK: Body
    var body: some View {
		NBList(.localized("Backup")) {
			Section {
				Button(.localized("Open Documents"), systemImage: "folder") {
					UIApplication.open(URL.documentsDirectory.toSharedDocumentsURL()!)
				}
			}
		}
    }
}
