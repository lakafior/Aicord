//
//  DemoImages.swift
//  Aicord
//

#if DEBUG
  import SwiftUI

  /// Answers image requests for demo avatars, server icons and attachments
  /// with pictures drawn on the spot, so demo mode needs no bundled photos
  /// and makes no network requests. Only URLs with a `demo-` name are taken.
  final class DemoImages: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
      guard let url = request.url, let host = url.host() else { return false }
      return (host == "cdn.discordapp.com" || host == "media.discordapp.net")
        && url.lastPathComponent.hasPrefix("demo-")
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
      request
    }

    override func startLoading() {
      guard let url = request.url else { return }
      Task { @MainActor in
        let data = DemoArt.png(for: url)
        let response = HTTPURLResponse(
          url: url, statusCode: 200, httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
      }
    }

    override func stopLoading() {}
  }

  /// The pictures behind `DemoImages`.
  @MainActor
  enum DemoArt {
    static func png(for url: URL) -> Data {
      let name = url.deletingPathExtension().lastPathComponent
      let size = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first { $0.name == "size" }?.value.flatMap(Double.init) ?? 256
      let view: AnyView
      let canvas: CGSize
      if let n = number(after: "demo-avatar-", in: name) {
        view = AnyView(Badge(symbol: avatarSymbols[n % avatarSymbols.count], palette: n))
        canvas = CGSize(width: size, height: size)
      } else if let n = number(after: "demo-icon-", in: name) {
        view = AnyView(Badge(symbol: iconSymbols[n % iconSymbols.count], palette: n + 3, rounded: true))
        canvas = CGSize(width: size, height: size)
      } else {
        let art = name.replacingOccurrences(of: "demo-art-", with: "")
        let (artView, artSize) = attachment(art)
        view = artView
        canvas = artSize
      }
      let renderer = ImageRenderer(content: view.frame(width: canvas.width, height: canvas.height))
      renderer.scale = 1
      #if os(macOS)
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:])
        else { return Data() }
        return data
      #else
        return renderer.uiImage?.pngData() ?? Data()
      #endif
    }

    private static func number(after prefix: String, in name: String) -> Int? {
      guard name.hasPrefix(prefix) else { return nil }
      return Int(name.dropFirst(prefix.count))
    }

    private static let avatarSymbols = [
      "sparkles", "hare.fill", "leaf.fill", "tortoise.fill", "moon.stars.fill", "fish.fill",
      "sun.max.fill", "headphones", "camera.macro", "bolt.fill", "ladybug.fill", "gearshape.2.fill",
    ]
    private static let iconSymbols = [
      "swift", "figure.hiking", "moon.zzz.fill", "books.vertical.fill", "paintpalette.fill",
    ]

    static let palettes: [[Color]] = [
      [.pink, .orange], [.orange, .yellow], [.mint, .teal], [.indigo, .purple],
      [.blue, .cyan], [.purple, .pink], [.yellow, .green], [.teal, .blue],
      [.green, .mint], [.red, .orange], [.cyan, .indigo], [.gray, .blue],
    ]

    private struct Badge: View {
      let symbol: String
      let palette: Int
      var rounded = false

      var body: some View {
        GeometryReader { proxy in
          ZStack {
            LinearGradient(
              colors: DemoArt.palettes[palette % DemoArt.palettes.count],
              startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol)
              .font(.system(size: proxy.size.width * 0.46, weight: .semibold))
              .foregroundStyle(.white)
              .shadow(color: .black.opacity(0.15), radius: proxy.size.width * 0.03)
          }
        }
      }
    }

    private static func attachment(_ name: String) -> (AnyView, CGSize) {
      switch name {
      case "weather":
        return (AnyView(WeatherShot()), CGSize(width: 645, height: 1398))
      case "icons-a", "icons-b":
        return (AnyView(IconSheet(offset: name == "icons-a" ? 0 : 6)), CGSize(width: 800, height: 800))
      default:
        return (AnyView(RailShot()), CGSize(width: 1200, height: 750))
      }
    }

    /// A phone screen of a made-up weather app with glass cards.
    private struct WeatherShot: View {
      var body: some View {
        ZStack {
          LinearGradient(colors: [.blue, .cyan.opacity(0.8), .orange.opacity(0.6)], startPoint: .top, endPoint: .bottom)
          VStack(spacing: 28) {
            VStack(spacing: 6) {
              Text("Lisbon").font(.system(size: 44, weight: .semibold))
              Text("21°").font(.system(size: 140, weight: .thin))
              Text("Mostly sunny").font(.system(size: 30))
            }
            .foregroundStyle(.white)
            .padding(.top, 140)
            card {
              HStack(spacing: 36) {
                ForEach(Array(zip(["Now", "14", "15", "16", "17"], ["sun.max.fill", "sun.max.fill", "cloud.sun.fill", "cloud.fill", "cloud.sun.fill"])), id: \.0) { hour, icon in
                  VStack(spacing: 14) {
                    Text(hour).font(.system(size: 24, weight: .medium))
                    Image(systemName: icon).symbolRenderingMode(.multicolor).font(.system(size: 34))
                    Text("2\(hour.count)°").font(.system(size: 26, weight: .medium))
                  }
                }
              }
            }
            card {
              VStack(alignment: .leading, spacing: 18) {
                Label("10-DAY FORECAST", systemImage: "calendar").font(.system(size: 20, weight: .semibold)).opacity(0.7)
                ForEach(["Today", "Tue", "Wed"], id: \.self) { day in
                  HStack {
                    Text(day).font(.system(size: 28, weight: .medium))
                    Spacer()
                    Capsule().fill(LinearGradient(colors: [.green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                      .frame(width: 220, height: 8)
                  }
                }
              }
            }
            Spacer()
          }
          .padding(.horizontal, 40)
          .foregroundStyle(.white)
        }
      }

      func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
          .padding(32)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(.white.opacity(0.22), in: .rect(cornerRadius: 40))
          .overlay(RoundedRectangle(cornerRadius: 40).stroke(.white.opacity(0.4), lineWidth: 2))
      }
    }

    /// A sheet of app icons.
    private struct IconSheet: View {
      let offset: Int
      var body: some View {
        ZStack {
          Color(white: 0.96)
          Grid(horizontalSpacing: 40, verticalSpacing: 40) {
            ForEach(0..<3) { row in
              GridRow {
                ForEach(0..<3) { column in
                  let n = offset + row * 3 + column
                  RoundedRectangle(cornerRadius: 46)
                    .fill(LinearGradient(colors: DemoArt.palettes[n % DemoArt.palettes.count], startPoint: .top, endPoint: .bottom))
                    .frame(width: 190, height: 190)
                    .overlay(
                      Image(systemName: ["checkmark", "drop.fill", "flame.fill", "book.fill", "figure.run", "bed.double.fill", "leaf.fill", "cup.and.saucer.fill", "brain.head.profile"][n % 9])
                        .font(.system(size: 84, weight: .semibold)).foregroundStyle(.white))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                }
              }
            }
          }
        }
      }
    }

    /// A Mac window with a narrow server rail.
    private struct RailShot: View {
      var body: some View {
        ZStack {
          LinearGradient(colors: [.indigo, .purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
          HStack(spacing: 0) {
            VStack(spacing: 22) {
              ForEach(0..<6) { n in
                RoundedRectangle(cornerRadius: 22)
                  .fill(LinearGradient(colors: DemoArt.palettes[(n + 3) % DemoArt.palettes.count], startPoint: .top, endPoint: .bottom))
                  .frame(width: 76, height: 76)
              }
              Spacer()
            }
            .padding(24)
            .background(.white.opacity(0.18))
            VStack(alignment: .leading, spacing: 18) {
              ForEach(0..<9) { n in
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(n == 2 ? 0.55 : 0.25))
                  .frame(width: n % 3 == 0 ? 180 : 260, height: 26)
              }
              Spacer()
            }
            .padding(36)
            .frame(width: 360, alignment: .leading)
            .background(.white.opacity(0.1))
            Color.white.opacity(0.85)
          }
          .clipShape(.rect(cornerRadius: 28))
          .padding(60)
          .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
        }
      }
    }
  }
#endif
