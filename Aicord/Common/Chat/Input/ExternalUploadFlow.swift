//
//  ExternalUploadFlow.swift
//  Aicord
//
//  A file over Discord's upload limit can go to the service chosen in
//  Settings → Chat instead. Each file is asked about first; once uploaded,
//  its link is added to the message being written.
//

import AicordKit
import SwiftUI
import UniformTypeIdentifiers

extension ChatView.InputBar.InputVM {
  struct ExternalUploadJob: Identifiable, Equatable {
    let id = UUID()
    var filename: String
  }

  /// A file waiting for the user to say yes, the first of `pendingExternalUploads`.
  var externalUploadToConfirm: URL? { pendingExternalUploads.first }

  /// The service a too-large file can go to, nil when none is set up or the
  /// file is too large for it as well.
  static func externalService(for size: Int) -> ExternalUpload.Service? {
    guard let service = ComposerPreferences.uploadService else { return nil }
    if let limit = service.sizeLimit, Int64(size) > limit { return nil }
    return service
  }

  func confirmExternalUpload() {
    guard let url = pendingExternalUploads.first,
      let service = ComposerPreferences.uploadService
    else { return }
    pendingExternalUploads.removeFirst()
    let filename = ComposerPreferences.uploadName(for: url.lastPathComponent)
    let job = ExternalUploadJob(filename: filename)
    externalUploads.append(job)
    let tracked = isTempFile(url)

    Task {
      defer { externalUploads.removeAll { $0.id == job.id } }
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      let stripped = ComposerPreferences.strippedPhoto(at: url)
      defer {
        if let stripped { try? FileManager.default.removeItem(at: stripped.deletingLastPathComponent()) }
        if tracked { discardTempFile(url) }
      }
      let contentType =
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
      do {
        let link = try await ExternalUpload.upload(
          file: stripped ?? url, filename: filename, contentType: contentType, to: service)
        let separator = content.isEmpty || content.hasSuffix(" ") || content.hasSuffix("\n") ? "" : " "
        content += separator + link.absoluteString
      } catch {
        externalUploadError = error.localizedDescription
      }
    }
  }

  func skipExternalUpload() {
    guard let url = pendingExternalUploads.first else { return }
    pendingExternalUploads.removeFirst()
    if isTempFile(url) { discardTempFile(url) }
  }

  /// "Upload “movie.mov” (240 MB) to catbox.moe?"
  func externalUploadQuestion(for url: URL) -> String {
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    let host = ComposerPreferences.uploadService?.host ?? ""
    return String(
      localized: "Upload “\(url.lastPathComponent)” (\(formatted)) to \(host)?")
  }
}

extension ChatView.InputBar {
  /// The question before each upload, the uploads in progress and their errors.
  struct ExternalUploadModifier: ViewModifier {
    @Bindable var inputVM: InputVM

    func body(content: Content) -> some View {
      content
        .confirmationDialog(
          inputVM.externalUploadToConfirm.map(inputVM.externalUploadQuestion) ?? "",
          isPresented: Binding(
            get: { inputVM.externalUploadToConfirm != nil },
            set: { shown in if !shown, inputVM.externalUploadToConfirm != nil { inputVM.skipExternalUpload() } }
          ),
          titleVisibility: .visible
        ) {
          Button("Upload and Add Link") { inputVM.confirmExternalUpload() }
          Button("Don't Upload", role: .cancel) { inputVM.skipExternalUpload() }
        } message: {
          Text(
            "It's larger than Discord takes. Anyone with the link can download it, and it stays on that service, not on Discord."
          )
        }
        .alert(
          "Upload Failed",
          isPresented: Binding(
            get: { inputVM.externalUploadError != nil },
            set: { if !$0 { inputVM.externalUploadError = nil } }
          )
        ) {
          Button("OK", role: .cancel) {}
        } message: {
          Text(inputVM.externalUploadError ?? "")
        }
    }
  }

  /// "Uploading movie.mov…" above the field while a large file goes up.
  struct ExternalUploadProgress: View {
    var inputVM: InputVM

    var body: some View {
      if !inputVM.externalUploads.isEmpty {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Group {
            if inputVM.externalUploads.count == 1 {
              Text("Uploading \(inputVM.externalUploads[0].filename)…")
            } else {
              Text("Uploading \(inputVM.externalUploads.count) files…")
            }
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .transition(.opacity)
      }
    }
  }
}
