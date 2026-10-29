//
//  ScanQRSection.swift
//  Paicord
//
//  Created by Lakhan Lothiyi on 23/01/2026.
//  Copyright © 2026 Lakhan Lothiyi.
//

import SwiftUI

#if os(iOS)
  import AVFoundation
  import AudioToolbox
  import UIKit
#endif

extension SettingsView {
  @ViewBuilder
  var scanQRSection: some View {
    #if os(iOS)
      Section("Scan QR Code") {
        QRCodeScanView()
          .listRowInsets(EdgeInsets())
          .listRowBackground(Color.clear)
      }
    #endif
  }
}

#if os(iOS)
  private struct QRCodeScanView: View {
    @Environment(\.gateway) var gw
    @Environment(\.appState) var appState
    @Environment(\.dismiss) var dismiss
    @State var scannedData: String? = nil
    @State var handshake_token: String? = nil

    var body: some View {
      if scannedData == nil {
        NativeQRScannerView { response in
          switch response {
          case .success(let string):
            do {
              try self.handleScannedString(string)
            } catch {
              appState.error = error
            }
          case .failure(let error):
            appState.error = error
          }
        }
        .frame(maxWidth: 300, maxHeight: 300)
        .clipShape(.rect(cornerRadius: 16))
      } else {
        VStack(spacing: 16) {
          if let token = handshake_token {
            Text("Remote Authentication")
              .font(.title2)
              .frame(maxWidth: .infinity, alignment: .center)

            AsyncButton("Log In") {
              try await gw.client.finishRemoteAuthSession(
                payload: .init(handshake_token: token)
              )
              .guardSuccess()
              dismiss()
            } catch: { error in
              appState.error = error
            }
            .buttonStyle(.borderedProminent)

            AsyncButton("Cancel") {
              try await gw.client.cancelRemoteAuthSession(
                payload: .init(handshake_token: token)
              )
              .guardSuccess()
              self.scannedData = nil
              self.handshake_token = nil
            } catch: { error in
              appState.error = error
            }
            .buttonStyle(.bordered)

            Text(
              "You are giving access to your Discord account to another device."
            )
            .foregroundStyle(.red)
          } else {
            ProgressView()
          }
        }
        .task {
          do {
            let req = try await gw.client.createRemoteAuthSession(
              payload: .init(fingerprint: self.scannedData!)
            )
            try req.guardSuccess()
            let data = try req.decode()
            self.handshake_token = data.handshake_token
          } catch {
            appState.error = error
            scannedData = nil
          }
        }
      }
    }

    enum QRCodeScanError: Error {
      case invalidURL
      case unrelatedURL
    }

    func handleScannedString(_ string: String) throws {
      guard let url = URL(string: string), UIApplication.shared.canOpenURL(url)
      else {
        throw QRCodeScanError.invalidURL
      }
      guard url.host?.contains("discord.com") == true else {
        throw QRCodeScanError.invalidURL
      }
      guard url.pathComponents.count >= 3,
        url.pathComponents[1] == "ra"
      else {
        throw QRCodeScanError.unrelatedURL
      }
      let fingerprint = url.pathComponents[2]
      self.scannedData = fingerprint
    }
  }

  private struct NativeQRScannerView: UIViewControllerRepresentable {
    var completion: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
      let vc = ScannerViewController()
      vc.completion = completion
      return vc
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
      var completion: ((Result<String, Error>) -> Void)?
      private let captureSession = AVCaptureSession()
      private var previewLayer: AVCaptureVideoPreviewLayer?
      private var didScan = false

      override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
          return
        }
        let videoInput: AVCaptureDeviceInput
        do {
          videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
          completion?(.failure(error))
          return
        }

        if captureSession.canAddInput(videoInput) {
          captureSession.addInput(videoInput)
        } else {
          return
        }

        let metadataOutput = AVCaptureMetadataOutput()
        if captureSession.canAddOutput(metadataOutput) {
          captureSession.addOutput(metadataOutput)
          metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
          metadataOutput.metadataObjectTypes = [.qr]
        } else {
          return
        }

        let preview = AVCaptureVideoPreviewLayer(session: captureSession)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        self.previewLayer = preview

        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
          session.startRunning()
        }
      }

      override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
      }

      override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = captureSession
        if session.isRunning {
          DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
          }
        }
      }

      func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
      ) {
        guard !didScan,
          let metadataObject = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
          let stringValue = metadataObject.stringValue
        else { return }

        didScan = true
        let session = captureSession
        DispatchQueue.global(qos: .userInitiated).async {
          session.stopRunning()
        }
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        completion?(.success(stringValue))
      }
    }
  }
#endif
