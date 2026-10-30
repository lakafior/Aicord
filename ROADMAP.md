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

### ✅ Etap 3: Oczyszczenie UI, komponentów pomocniczych i wprowadzenie Liquid Glass (ZAKOŃCZONY)
1. **`VariableBlurView.swift` (Prywatne API `CABackdropLayer` / `CAFilter` w base64) -> Natywne materiały / Liquid Glass:**
   - [x] Zastąpienie hacków opartych na prywatnych klasach QuartzCore natywnymi efektami rozmycia i **Liquid Glass** z iOS/macOS 26 (`.glassEffect()`, `GlassEffectContainer`, natywne materiały SwiftUI).
2. **`Sparkle` (Auto-updater macOS):**
   - [x] Usunięcie paczki `https://github.com/sparkle-project/Sparkle` i powiązanego kodu w `PaicordApp.swift`.
3. **`SwiftUIIntrospect` (`swiftui-introspect`):**
   - [x] Usunięcie paczki `https://github.com/siteline/swiftui-introspect`.
   - [x] Zastąpienie 6 miejsc użycia natywnymi modyfikatorami z macOS/iOS 26 (`.restorationBehavior(.disabled)`, `.toolbarBackgroundVisibility(..., for: .windowToolbar)`, `.onScrollPhaseChange`, natywne przełączanie kart).
4. **`SettingsKit`:**
   - [x] Usunięcie paczki `https://github.com/Aeastr/SettingsKit`.
   - [x] Zastąpienie prostym, natywnym układem `NavigationSplitView` / `Form` (`.formStyle(.grouped)`) w czystym SwiftUI.
5. **`HCaptcha`:**
   - [x] Usunięcie zewnętrznej paczki `https://github.com/llsc12/hcaptcha` i zastąpienie jej czystym `WKWebView` bezpośrednio w `CaptchaSheet.swift`.
6. **`Lottie`:**
   - [x] Usunięcie `lottie-spm` (używanego tylko w `StickersView.swift`) i zastąpienie lekkim natywnym parserem/rendererem wektorowym (`Canvas` + `TimelineView`, wzorowanym na podejściu `rasterlottie` z Serein).

---

### ✅ Etap 4: Eliminacja `SwiftUIX` i głęboka modernizacja architektury (ZAKOŃCZONY)
1. **Usunięcie `SwiftUIX` (`https://github.com/llsc12/SwiftUIX`):**
   - [x] Zamiana `import SwiftUIX` na `import SwiftUI` we wszystkich 69 plikach.
   - [x] Zastąpienie `IntrinsicSizeReader` natywnym modyfikatorem `.onGeometryChange(for: CGSize.self)` (dostępnym natywnie w nowym SwiftUI!).
   - [x] Zastąpienie `@ViewStorage` standardowym `@State` lub `@ObservationIgnored`.
   - [x] Zastąpienie helperów typu `.maxWidth()`, `.minHeight()`, `AppKitOrUIKitViewRepresentable`, `Image(cgImage:)` czystym SwiftUI.
2. **Odchudzenie `Textual` / Markdown i pozostałych paczek (`SwiftEmoji`, `Nuke`, `PaicordLib`):**
   - [x] Usunięcie `swift-concurrency-extras` oraz `swiftui-math` z `Textual/Package.swift` (0 zewnętrznych zależności w `Textual`!).
   - [x] Usunięcie `SwiftEmoji` / `SwiftEmojiIndex` (`https://github.com/Aeastr/SwiftEmoji`) — kategoryzacja, wyszukiwanie i indeksowanie emoji oparte bezpośrednio na natywnym `DiscordEmojiNameIndex` (`DiscordEmojiNames.json`) bez duplikacji bazy.
   - [x] Usunięcie `Nuke` / `NukeUI` (`https://github.com/kean/Nuke.git`) — zastąpienie lekkim, natywnym `actor ImagePipeline` (`URLSession` + `URLCache` + `NSCache` + `ImageIO` + współdzielony `AnimatedImageFrameSource`).

---

### ⏳ Etap 5: Optymalizacja Architektury, Sieci i Rebranding do Aicord
1. **Strict Concurrency & Porządki w Store'ach (Swift 6):**
   - [x] Oznaczenie Store'ów (`GatewayStore`, `GuildStore`, `ChannelStore`, `CurrentUserStore` itd.) jako `@MainActor` i usunięcie zbędnych bloków `Task { @MainActor in }` oraz komunikacji przez `NotificationCenter`.
   - [x] Przełączenie targetu aplikacji na `SWIFT_VERSION = 6.0` (build macOS + iOS bez błędów i bez ostrzeżeń współbieżności). Znane blokery: statyczne mutowalne stany (`PaicordAppState.instances`/`sharedEphemeral`, `transcriptCache`/`waveformCache` w `Attachments.swift`, `defaultGradientMask` w `VariableBlurView.swift`, `ShellView`), typy non-Sendable w `DownloadButton.swift`, `Sending 'self'` w `Task { @MainActor in }` Store'ów. Nie maskować tego przez `@unchecked Sendable`.
2. **Odchudzenie Logowania, Zasobów i `Textual`:**
   - [x] Wyłączenie domyślnego przechwytywania `stdout`/`stderr` w `StdOutInterceptor.swift` (trzymającego logi w tablicy w RAM-ie) na rzecz lekkiego, natywnego `os.Logger` (`OSLog`).
   - [x] Leniwe ładowanie (lazy loading) i deduplikacja słownika emoji (`DiscordEmojiNames.json`).
   - [x] Zastąpienie zasobu `prism-bundle.js` i `JavaScriptCore` (`JSContext`) w `Textual` (`CodeTokenizer.swift`) lekkim, natywnym tokenizerem składni w czystym Swifcie (bez silnika JS w tle).
3. **Migracja warstwy sieciowej `PaicordLib` na natywne API Apple:**
   - [x] Zastąpienie ciężkiego, serwerowego stosu `SwiftNIO` (`swift-nio`, `async-http-client`, `swift-websocket`, `multipart-kit`, `swift-crypto`) natywnym `URLSession` (`URLSessionWebSocketTask`, HTTP/3) oraz systemowym `CryptoKit`.
   - [x] Przeniesienie testów jednostkowych `DiscordBMTests` z `NIOCore`/`NIOHTTP1`/`swift-atomics` na natywne typy (`HTTPHeaders`, `Data`, `Synchronization.Atomic`) — 83 testy przechodzą. Usunięte: `IntegrationTests` (wymagały bota i serwera testowego autora DiscordBM), `DecompressionTests` (testowały nieistniejący już dekompresor zlib) i martwy test `DiscordCache`.
4. **Rebranding `Paicord` → `Aicord`:**
   - [x] Usunięcie zewnętrznych odznak sponsorów/telemetrii w `ExternalBadgeStore.swift`.
   - [x] Zmiana identyfikatora Bundle ID (`net.smigi.aicord`).
   - [ ] Zmiana nazw targetów/schematów (`Paicord` → `Aicord`) oraz odniesień do oryginalnego repozytorium.

---

### 🔜 Etap 6: Tożsamość Aicord, poprawki i dokumentacja
1. **Ikona aplikacji:**
   - [x] Nowa ikona `Paicord/Resources/AppIcon.icon` z Icon Composer: uproszczone płaskie dymki w pomarańczu w stylu Claude, każdy element jako osobna warstwa Liquid Glass, kremowe tło w trybie jasnym i grafitowe w ciemnym. Zastępuje `AppIcon.appiconset`; `AppIcon.imageset` (ekran łączenia) dostał render nowej ikony.
2. **Poprawki błędów:**
   - [x] fix: wejście na kanał i przeczytanie nowych wiadomości nie oznacza ich jako przeczytane. `ChatView` wysyła ack przy wejściu na kanał, po przewinięciu na dół i po powrocie do aplikacji; pozycja `nil` (widok na dolnej kotwicy) liczy się jako „na dole”.
3. **README:**
   - [x] Powód forka: blokada PR-ów tworzonych ze wsparciem AI w głównym repozytorium.
   - [x] Lista zmian względem oryginalnego kodu (podsumowanie Etapów 1–5).
   - [x] Usunięcie linków do pobrania oryginalnej aplikacji.
   - [x] Przebudowa README od nowa w nowoczesnej formie.

---

### 🔜 Etap 7: Własne biblioteki zamiast forków (`PaicordLib`, `Textual`)
`PaicordLib` (przerobiony DiscordBM) i `Textual` zostają lokalnymi paczkami SPM — osobne moduły dają szybszą kompilację przyrostową, testy przez `swift test` i miejsce na target makr. Traktujemy je jednak jako własny kod, bez synchronizacji z upstreamem.
1. **Odchudzenie `DiscordModels` (~6,9 MB z ~18,5 MB kodu arm64):**
   - [ ] Usunięcie modeli i endpointów tylko dla botów: interakcje, komendy aplikacji, logi audytu, automoderacja, webhooki.
   - [ ] Usunięcie infrastruktury shardowania botów (`ShardCoordinator` i powiązane).
   - [ ] Ograniczenie kodu kopiowania generowanego dla dużych struktur z wieloma polami opcjonalnymi (`Guild`, `Gateway.Ready` itd., ~2,9 MB).
2. **Uproszczenie modułów `PaicordLib`:**
   - [ ] Scalenie prawie pustych bibliotek (`DiscordCore`, `DiscordAuth`, `DiscordUtilities`) w 2–3 sensowne moduły.
   - [ ] Zmiana nazwy na własną (np. `AicordKit`) i usunięcie pozostałości DiscordBM (komentarze, przestarzałe API dla botów).
3. **`Textual`:**
   - [ ] Usunięcie elementów, których aplikacja nie renderuje.

---

### ⏳ Etap 8: Odświeżenie UI
Przed pracą nad voice. Plan zaakceptowany 30.10.2026.
1. **Poprawki (zrobione):**
   - [x] fix: aplikacja na macOS padała kilka sekund po załadowaniu. Kolumna czatu i lista członków (`.inspector` w kolumnie detali `NavigationSplitView`) przepychały się minimalnymi szerokościami w pętli, aż AppKit rzucał wyjątek o wyczerpaniu przebiegów Update Constraints. Czat i lista członków mają stałą minimalną szerokość, okno startuje w rozmiarze 1280×800 i ma minimum 960×540. Przeniesienie `.inspector` na sam split view też usuwa crash, ale wtedy `LazyVStack` listy członków się nie rysuje.
   - [x] Usunięcie `UIDesignRequiresCompatibility` z `Info.plist`: flaga kazała iOS 26 rysować aplikację w starym stylu, bez Liquid Glass w systemowych paskach, zakładkach i arkuszach. Do przejrzenia po zalogowaniu, czy własne tła i materiały nie gryzą się z systemowym szkłem.
   - [x] fix: lista członków startowała z pozycją przewinięcia 0 przy kotwicy `.bottom`, więc mogła uciec poza widok.
   - [x] Nagłówek kanału bez szklanej pigułki: na iOS strzałka wstecz zostaje sama, a ikona i nazwa kanału są tytułem na środku paska (skracane wielokropkiem, gdy brakuje miejsca). Na macOS nazwa serwera i kanału to zwykłe tytuły paska okna. Do sprawdzenia zrzutem na iOS.
2. **Nawigacja na iPhonie:**
   - [ ] Usunięcie zakładki Powiadomienia (pokazuje tylko napis zastępczy, nie pobiera danych).
   - [ ] Ustawienia jako zakładka skrajnie po prawej (bez przycisku „Done”); zębatka znika z Profilu.
3. **Profil:**
   - [ ] Działający wybór statusu (online, zaraz wracam, nie przeszkadzać, niewidoczny) przez `setPresence` i `modifyUserSettingsProto`; dziś przyciski w `ProfileButtonPopout` są puste. Ten sam wybór w popoverze `ProfileBar` na macOS.
   - [ ] Podgląd i edycja custom statusu (emoji i tekst).
   - [ ] „Konto od” (data z identyfikatora użytkownika).
   - [ ] Konta: lista z przełączaniem, „Dodaj konto”, „Wyloguj”.
   - [ ] „Edytuj profil” jako link do ustawień profilu w przeglądarce zamiast wyłączonego przycisku.
4. **Ustawienia:**
   - [x] Sekcja „Paicord” → „O Aicord”: wersja, build, licencja GPL-3, link do repozytorium; bez „Made with ❤️ by llsc12”, naklejki z CDN Discorda i przycisku Donate. Na dole dopisek, że to fork Paicorda od llsc12.
   - [ ] Moje konto: dane konta, przełączanie kont, wylogowanie (Scan QR na iOS zostaje).
   - [ ] Skróty klawiszowe (macOS): lista istniejących skrótów (⌘, ⌘K, ⇧⌘R).
   - [x] Debug: bez przycisku podglądu okna sponsora.
   - [ ] Puste sekcje („Coming Soon”) zostają jako miejsca na przyszłe ustawienia.
5. **Pozostałości po Paicordzie poza Ustawieniami:**
   - [x] Usunięcie `SponsorSheet` (samo wyskakuje po 2 dniach z linkiem do sponsorowania llsc12).
   - [x] Usunięcie `UpdateCheck` i `SUFeedURL` (czyta kanał wydań llsc12, więc proponowałby pobranie oryginalnego Paicorda); razem z resztą kluczy Sparkle w `Info.plist`.
   - [x] „Aicord” zamiast „Paicord” na ekranie łączenia (bez „SwiftUI ftw”), w tekście przy kodzie QR logowania, w tytule okna logów i jako autor wbudowanych motywów.
   - [x] Nazwa wyświetlana aplikacji „Aicord” (`CFBundleDisplayName`: ekran główny iOS). Menu i Dock na macOS biorą nazwę z `PRODUCT_NAME`, więc zmienią się dopiero razem z targetem (Etap 5.4). Klucze `UserDefaults` i wewnętrzne linki `paicord://` zostają.
   - [x] Opisy uprawnień (aparat, mikrofon, ruch, rozpoznawanie mowy) zamiast żartobliwych tekstów.
   - [x] Usunięcie `.github/FUNDING.yml` (przycisk Sponsor prowadził do llsc12) oraz workflowów `build.yml` i `release_pr.yml` (podpisywanie, Sparkle i webhooki Discorda na sekretach llsc12). `build_pr.yml` zostaje jako budowanie PR-ów bez podpisu.
   - [x] Usunięcie z `Localizable.xcstrings` tekstów po usuniętych ekranach.
   - [x] Usługa w pęku kluczy `net.smigi.aicord.Accounts` (zamiast `com.llsc12.Paicord.Accounts`) i katalog cache obrazków `net.smigi.aicord.imagecache`. Wymaga ponownego zalogowania; stary wpis `com.llsc12.Paicord.Accounts` można usunąć w Pęku kluczy.
6. **Weryfikacja:**
   - [ ] Build macOS (arm64) i iOS bez nowych ostrzeżeń, zrzuty ekranu z obu platform.

---

### 🔜 Etap 9: Voice — kanały głosowe i rozmowy w DM
Startujemy po odświeżeniu UI. To port, nie merge. Bazą kodu jest gałąź [`upstream/voice`](https://github.com/llsc12/Paicord/tree/voice): działający szkic w Swifcie (dźwięk w obie strony, DAVE przez DaveKit, rozmowy w DM z dzwonieniem), ale odstaje o 126 commitów od upstream `main` i stoi na usuniętym w Etapie 5 stosie NIO. Wzorcem zachowania jest [Serein](https://github.com/ViceVerse-cz/Serein) (Rust, MIT/Apache, więc wolno adaptować do GPL-3): `crates/discord-voice/README.md`, `docs/voice.md`, `transport.rs` i `crypto.rs`. Jego DAVE (`davey`/OpenMLS) i audio (CPAL, Sonora, RNNoise) nie nadają się dla Swifta, więc bierzemy z niego zachowanie, nie kod.
1. **Modele (`DiscordModels`):**
   - [ ] Przeniesienie z gałęzi voice `VoiceGateway.swift`, `VoiceGateway+Payloads.swift` i `RTP/` (RTP, RTCP, RTPType) oraz zmian voice-state w `Gateway.swift`, `Guild.swift` i `Voice.swift`. `ByteBuffer` → `Data`.
2. **Transport (`DiscordVoice`, bez NIO, AsyncHTTPClient, WSClient i Atomics):**
   - [ ] WebSocket voice v8 na `URLSessionWebSocketTask`, jak w `UserGatewayManager`; UDP na Network.framework (`NWConnection`).
   - [ ] Maszyna stanów jak w Serein: Resume z `seq_ack`, jeden niepotwierdzony heartbeat dozwolony, po drugim resume; najwyżej dwa resume z rzędu, potem ponowne dołączenie.
   - [ ] Limity czasu: połączenie 15 s, UDP discovery 8 s, negocjacja DAVE 90 s (30 s dla kolejnego przejścia); UDP keepalive.
   - [ ] Adresy UDP tylko publiczne i tylko te podane przez serwer; host WebSocket tylko z domen mediów Discorda.
3. **Szyfrowanie transportu (CryptoKit, bez swift-crypto):**
   - [ ] `aead_aes256_gcm_rtpsize` (preferowany) przez `AES.GCM`.
   - [ ] `aead_xchacha20_poly1305_rtpsize` (wymagany przez Discorda) jako własne HChaCha20 plus `ChaChaPoly` z CryptoKit.
   - [ ] Testy z wektorami testowymi dla obu trybów rtpsize.
4. **DAVE (E2EE):**
   - [ ] `llsc12/DaveKit` (oficjalny libdave przez C++ interop), przypięty do konkretnego commitu. `.interoperabilityMode(.Cxx)` tylko w targecie `DiscordVoice`; sprawdzić, czy nie psuje Swift 6 language mode w innych targetach.
   - [ ] Zabezpieczenia z Serein: odrzucanie nieoczekiwanego ID grupy, użytkowników spoza listy uczestników, duplikatów i propozycji innych niż Add/Remove.
   - [ ] Odzyskiwanie przy nieprawidłowej grupie; żadnych mediów przed zakończeniem przejścia; logi bez sekretów.
5. **Audio i aplikacja:**
   - [ ] `VoiceConnectionStore.swift` z gałęzi voice: AVAudioEngine z voice processing (redukcja echa i szumu z systemu zamiast Sonora/RNNoise), Opus przez `swift-opus`.
   - [ ] Jitter buffer i PLC jak w Serein: 8 pakietów na mówcę, start po 40 ms, najwyżej 3 pakiety PLC.
   - [ ] `VoiceChannelsStore.swift`, `PCMFloatRingBuffer.swift`, uczestnicy kanałów głosowych w liście kanałów.
   - [ ] UI: `VoiceView`, `CallView` i pasek rozmowy w `ProfileBar`, dopasowane do Liquid Glass i obecnej nawigacji.
   - [ ] Wyciszenie, wyłączenie dźwięku, wybór urządzeń wejścia i wyjścia, push-to-talk.
   - [ ] Nie przenosimy usunięć z gałęzi voice (`DiscordCache`, `GatewayEventHandler`, `BotAuthManager`), zmian nawigacji w `PaicordAppState` ani starych zależności.
6. **Weryfikacja:**
   - [ ] PaicordLib i aplikacja (macOS, arm64) się budują, testy przechodzą.
   - [ ] Ręczny test na koncie: dźwięk w obie strony z DAVE w DM, w rozmowie grupowej i na kanale serwera; dołączanie i wychodzenie uczestników; wznowienie po zerwaniu sieci.
7. **Później:**
   - [ ] Wideo i udostępnianie ekranu. Serein ma do tego ścieżki na macOS (ScreenCaptureKit, VideoToolbox).
