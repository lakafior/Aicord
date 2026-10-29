# Paicord — Roadmap Oczyszczania i Modernizacji (Pure Swift 6 & OS 26 Liquid Glass)

## Cel główny
Przekształcenie projektu **Paicord** w czystą, szybką i łatwą w utrzymaniu aplikację opartą na:
- **Język:** Czysty **Swift 6** (`SWIFT_VERSION = 6.0`)
- **Minimalne wersje systemów:** **iOS 26.0** oraz **macOS 26.0**
- **UI & Design:** Natywne **SwiftUI** z wykorzystaniem nowego stylu **Liquid Glass** (natywne materiały, rozmycia, `SwiftUI.MeshGradient`, brak prywatnych hacków `CAFilter`/`CABackdropLayer`, brak zewnętrznych shaderów Metal i bibliotek Objective-C).

---

## Status Etapów

### ✅ Etap 1: Usunięcie martwych i debugowych zależności (ZAKOŃCZONY)
- [x] **`SwiftPrettyPrint`** (+ 5 pod-zależności: `ColorizeSwift`, `Curry`, `Flatten`, `SHList`, `SwiftParamTest`) — usunięto nieużywane importy i paczkę SPM.
- [x] **`Conditionals`** — usunięto nieużywany import i paczkę SPM.
- [x] **`Loupe`** — usunięto modyfikatory `.debugRender()` / `.debugCompute()` i paczkę SPM.
- [x] **`FLEX`** — usunięto narzędzie Objective-C z `DebugSection.swift` i paczkę SPM.
- [x] **`Yams`** — usunięto z `PaicordLib/Package.swift` wraz z nieużywanym pluginem `GenerateAPIEndpoints`.
- [x] **`swift-snapshot-testing`** (+ `swift-custom-dump`, `swift-issue-reporting`) — usunięto z `Textual/Package.swift`.

---

### ✅ Etap 2: Podniesienie wersji do Swift 6 + iOS/macOS 26 oraz zamiana bibliotek na natywne API Apple (ZAKOŃCZONY)
Dzięki ustawieniu **iOS 26 / macOS 26** oraz **Swift 6**, zyskujemy dostęp do najnowszych wbudowanych funkcji systemowych bez żadnych fallbacków dla starych systemów:

1. **Konfiguracja Projektu i Pakietów:**
   - [x] Ustawienie `MACOSX_DEPLOYMENT_TARGET = 26.0` i `IPHONEOS_DEPLOYMENT_TARGET = 26.0` w `Paicord.xcodeproj` (toolchain Swift 6.2; target aplikacji zostaje w trybie językowym Swift 5 — przejście na tryb Swift 6 przeniesione do Etapu 5).
   - [x] Aktualizacja platform w `PaicordLib/Package.swift` i `Textual/Package.swift`.
   - [x] Usunięcie warunkowych sprawdzeń `#available(iOS 26.0, macOS 26.0, *)` (np. w `LoginView.swift` przy generowaniu zaokrąglonych kodów QR `CIFilter.roundedQRCodeGenerator()`).

2. **`MeshGradient` + `MeshGradientCHeaders` (Zewnętrzny Metal + C Headers) -> Natywny `SwiftUI.MeshGradient`:**
   - [x] Usunięcie paczki `https://github.com/patskovn/MeshGradient`.
   - [x] Przepisanie `Paicord/Common/Login/MeshGradient.swift` na wbudowany w system `SwiftUI.MeshGradient` z płynną animacją (`TimelineView` / `PhaseAnimator`).

3. **`MijickCamera` (`Camera` + `Timer`) -> Natywny `CameraPicker`:**
   - [x] Usunięcie paczki `https://github.com/Mijick/Camera`.
   - [x] Podpięcie istniejącego w projekcie natywnego `CameraPicker.swift` (`UIImagePickerController`) w `InputBar.swift`.

4. **`KeychainAccess` -> Natywny `Security` Framework:**
   - [x] Usunięcie paczki `https://github.com/kishikawakatsumi/KeychainAccess`.
   - [x] Zastąpienie zapisu/odczytu w `TokenStore.swift` lekkim, czystym wrapperem na `SecItemCopyMatching` / `SecItemAdd` / `SecItemUpdate`.

5. **`ColorCube` (Objective-C) -> Natywny `CoreImage` / `CGContext`:**
   - [x] Usunięcie paczki `https://github.com/llsc12/ColorCube`.
   - [x] Zastąpienie ekstrakcji koloru avatara w `ProfilePopoutView.swift`, `DMProfilePanel.swift` i `ProfileView.swift` czystą funkcją w Swift (np. `CIAreaAverage` / szybki sampling pikseli).

6. **`CodeScanner` -> Natywny skaner QR (`VisionKit` / `AVFoundation`):**
   - [x] Usunięcie paczki `https://github.com/twostraws/CodeScanner`.
   - [x] Zastąpienie skanera w `ScanQRSection.swift` natywnym `DataScannerViewController` (`VisionKit`) lub `AVCaptureSession`.

7. **`UInt128` (w `PaicordLib`) -> Natywny `Swift.UInt128`:**
   - [x] Usunięcie paczki `https://github.com/Jitsusama/UInt128.git` z `PaicordLib/Package.swift` — Swift 6 posiada wbudowany typ `UInt128` w bibliotece standardowej.

---

### ⏳ Etap 3: Oczyszczenie UI, komponentów pomocniczych i wprowadzenie Liquid Glass
1. **`VariableBlurView.swift` (Prywatne API `CABackdropLayer` / `CAFilter` w base64) -> Natywne materiały / Liquid Glass:**
   - [ ] Zastąpienie hacków opartych na prywatnych klasach QuartzCore natywnymi efektami rozmycia i **Liquid Glass** z iOS/macOS 26 (`.glassEffect()`, natywne materiały SwiftUI).
2. **`Sparkle` (Auto-updater macOS):**
   - [ ] Usunięcie paczki `https://github.com/sparkle-project/Sparkle` i powiązanego kodu w `PaicordApp.swift`.
3. **`SwiftUIIntrospect` (`swiftui-introspect`):**
   - [ ] Usunięcie paczki `https://github.com/siteline/swiftui-introspect`.
   - [ ] Zastąpienie 6 miejsc użycia natywnymi modyfikatorami z macOS/iOS 26 (np. `.windowRestorationBehavior(.disabled)`, `. onScrollPhaseChange` z nowego SwiftUI!).
4. **`SettingsKit`:**
   - [ ] Usunięcie paczki `https://github.com/Aeastr/SettingsKit`.
   - [ ] Zastąpienie prostym, natywnym układem `NavigationSplitView` / `Form` w czystym SwiftUI.
5. **`HCaptcha`:**
   - [ ] Usunięcie zewnętrznej paczki `https://github.com/llsc12/hcaptcha` i zastąpienie jej czystym `WKWebView` bezpośrednio w `CaptchaSheet.swift`.
6. **`Lottie`:**
   - [ ] Usunięcie `lottie-spm` (używanego tylko w `StickersView.swift`) lub zastąpienie lekkim natywnym rozwiązaniem.

---

### ⏳ Etap 4: Eliminacja `SwiftUIX` i głęboka modernizacja architektury
1. **Usunięcie `SwiftUIX` (`https://github.com/llsc12/SwiftUIX`):**
   - [ ] Zamiana `import SwiftUIX` na `import SwiftUI` we wszystkich 69 plikach.
   - [ ] Zastąpienie `IntrinsicSizeReader` natywnym modyfikatorem `.onGeometryChange(for: CGSize.self)` (dostępnym natywnie w nowym SwiftUI!).
   - [ ] Zastąpienie `@ViewStorage` standardowym `@State` lub `@ObservationIgnored`.
   - [ ] Zastąpienie helperów typu `.maxWidth()`, `.minHeight()`, `AppKitOrUIKitViewRepresentable`, `Image(cgImage:)` czystym SwiftUI.
2. **Odchudzenie `Textual` / Markdown i pozostałych paczek (`SwiftEmoji`, `Nuke`, `PaicordLib`):**
   - [ ] Usunięcie `swift-concurrency-extras` z `Textual/Package.swift`.
   - [ ] Przegląd i ewentualna zamiana pozostałych zależności (`swiftui-math`, duplikacja danych emoji między `DiscordEmojiNames.json` 1.9 MB a `SwiftEmojiIndex`).

---

### ⏳ Etap 5: Optymalizacja Architektury, Sieci i Rebranding do Aicord
1. **Strict Concurrency & Porządki w Store'ach (Swift 6):**
   - [ ] Oznaczenie Store'ów (`GatewayStore`, `GuildStore`, `ChannelStore`, `CurrentUserStore` itd.) jako `@MainActor` i usunięcie zbędnych bloków `Task { @MainActor in }` oraz komunikacji przez `NotificationCenter`.
   - [ ] Przełączenie targetu aplikacji na `SWIFT_VERSION = 6.0`. Znane blokery: statyczne mutowalne stany (`PaicordAppState.instances`/`sharedEphemeral`, `transcriptCache`/`waveformCache` w `Attachments.swift`, `defaultGradientMask` w `VariableBlurView.swift`, `ShellView`), typy non-Sendable w `DownloadButton.swift`, `Sending 'self'` w `Task { @MainActor in }` Store'ów. Nie maskować tego przez `@unchecked Sendable`.
2. **Odchudzenie Logowania i Zasobów:**
   - [ ] Wyłączenie domyślnego przechwytywania `stdout`/`stderr` w `StdOutInterceptor.swift` (trzymającego logi w tablicy w RAM-ie) na rzecz lekkiego, natywnego `os.Logger` (`OSLog`).
   - [ ] Leniwe ładowanie (lazy loading) i deduplikacja słownika emoji (`DiscordEmojiNames.json`).
3. **Migracja warstwy sieciowej `PaicordLib` na natywne API Apple:**
   - [ ] Zastąpienie ciężkiego, serwerowego stosu `SwiftNIO` (`swift-nio`, `async-http-client`, `swift-websocket`, `multipart-kit`, `swift-crypto`) natywnym `URLSession` (`URLSessionWebSocketTask`, HTTP/3) oraz systemowym `CryptoKit`.
4. **Rebranding `Paicord` → `Aicord`:**
   - [ ] Usunięcie zewnętrznych odznak sponsorów/telemetrii w `ExternalBadgeStore.swift`.
   - [ ] Zmiana nazw targetów, identyfikatorów Bundle ID oraz odniesień do oryginalnego repozytorium.
