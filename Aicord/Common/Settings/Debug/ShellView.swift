//
//  ShellView.swift
//  Aicord
//
//  Created by Lakhan Lothiyi on 21/11/2025.
//  Copyright © 2025 Lakhan Lothiyi.
//

import SwiftUI

struct ShellView: View {
  @StateObject private var vm = ShellViewModel()
  @State private var doScrolling = true
  @State private var scrollTask: Task<Void, Never>? = nil

  @State private var fontSize =
    UserDefaults.standard.value(forKey: "Shell.FontSize") as? CGFloat ?? 12
  {
    didSet { UserDefaults.standard.set(self.fontSize, forKey: "Shell.FontSize") }
  }
  let _FontSizeRange: ClosedRange<CGFloat> = 6...18

  @State private var keepPinned =
    UserDefaults.standard.value(forKey: "Shell.KeepPinned") as? Bool ?? true
  {
    didSet { UserDefaults.standard.set(self.keepPinned, forKey: "Shell.KeepPinned") }
  }

  var body: some View {
    GeometryReader { outer in
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(vm.logs) { item in
              cell(item)
                .background {
                  if item.type != .out {
                    Rectangle()
                      .fill(item.type == .err ? .yellow : .red)
                      .opacity(0.15)
                  }
                }
            }
            // bottom anchor
            Text(verbatim: "")
              .id("bottom")
              .frame(height: 0)
              .background(
                GeometryReader { geo in
                  Color.clear.preference(
                    key: BottomPositionPreferenceKey.self,
                    value: geo.frame(in: .named("logScroll")).minY)
                }
              )
          }
        }
        .coordinateSpace(name: "logScroll")
        .navigationTitle("Aicord Logs")
        .font(.system(size: fontSize, weight: .regular, design: .monospaced))
        .multilineTextAlignment(.leading)
        .toolbarTitleDisplayMode(.inline)
        .onReceive(vm.$logs) { _ in
          if doScrolling {
            proxy.scrollTo("bottom")
          }
        }
        .onPreferenceChange(BottomPositionPreferenceKey.self) { bottomY in
          guard let bottomY = bottomY else { return }

          let visibleHeight = outer.size.height
          let threshold: CGFloat = 20
          let bottomIsVisible = bottomY <= (visibleHeight + threshold)

          if bottomIsVisible {
            self.scrollTask?.cancel()
            self.scrollTask = Task {
              try? await Task.sleep(for: .seconds(5))
              guard !Task.isCancelled else { return }
              withAnimation { proxy.scrollTo("bottom") }
              try? await Task.sleep(for: .milliseconds(500))
              self.doScrolling = true
            }
          } else {
            self.scrollTask?.cancel()
            self.scrollTask = nil
            if self.doScrolling { self.doScrolling = false }
          }
        }
        .onDisappear {
          self.scrollTask?.cancel()
          self.scrollTask = nil
        }
      }
    }
    .background {
      Rectangle()
        .fill(Color(hue: 0.6416666667, saturation: 0.07, brightness: 0.17))
        .ignoresSafeArea()
    }
    #if !os(watchOS) && !os(macOS)
      .toolbar {
        Menu {
          Slider(value: $fontSize, in: self._FontSizeRange)
        } label: {
          Image(systemName: "gear")
        }
      }
    #endif
  }

  @ViewBuilder
  func cell(_ log: StdOutInterceptor.LogItem) -> some View {
    Group {
      let txt = Text(log.str.trimmingCharacters(in: .whitespacesAndNewlines))
        .frame(maxWidth: .infinity, alignment: .leading)

      #if !os(watchOS)
        txt
          .contextMenu {
            Button("Copy") {
              #if os(iOS)
                UIPasteboard.general.string = log.str
              #elseif os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(log.str, forType: .string)
              #endif
            }
          }
      #else
        txt
      #endif
      Divider()
    }
  }
}

private struct BottomPositionPreferenceKey: PreferenceKey {
  static let defaultValue: CGFloat? = nil
  static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
    value = nextValue() ?? value
  }
}

@MainActor
final class ShellViewModel: ObservableObject {
  @Published var logs: [StdOutInterceptor.LogItem] = []
  nonisolated(unsafe) private var observation: NSObjectProtocol?

  init() {
    // Load initial logs once
    self.logs = StdOutInterceptor.shared.getLogs()

    // Subscribe to incremental log notifications (object is [LogItem])
    self.observation = NotificationCenter.default.addObserver(
      forName: .newLogAdded, object: nil, queue: .main
    ) { [weak self] note in
      guard let items = note.object as? [StdOutInterceptor.LogItem], !items.isEmpty else { return }
      Task { @MainActor [weak self] in
        self?.logs.append(contentsOf: items)
      }
    }
  }

  deinit {
    if let obs = observation { NotificationCenter.default.removeObserver(obs) }
  }
}
