// MARK: - View
import NimbleViews
//
//  ArchiveView.swift
//  Feather
//
//  Created by samara on 6.05.2025.
//

import SwiftUI

import Zip

struct ArchiveView: View {
  //@AppStorage("SayStore.useShareSheetForArchiving") private var _useShareSheet: Bool = false

  // MARK: Body
  var body: some View {
    NBList(.localized("Backup")) {
      Section {
        Picker(
          .localized("Compression Level"), systemImage: "archivebox", selection: $_compressionLevel
        ) {
          ForEach(ZipCompression.allCases, id: \.rawValue) { level in
            Text(level.label).tag(level)
          }
        }
      }

      Section {
        Toggle(
          .localized("Show Sheet when Exporting"), systemImage: "square.and.arrow.up",
          isOn: $_useShareSheet)
      } footer: {
        Text(
          .localized(
            "Toggling show sheet will present a share sheet after exporting to your files."))
      }
    }
  }
}
