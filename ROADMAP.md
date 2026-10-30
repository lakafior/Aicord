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
4. **Porządek w dokumentacji** (po scaleniu sesji, które teraz zmieniają ROADMAP i README, żeby nie było konfliktów):
   - [ ] `ROADMAP.md`: tylko to, co jeszcze do zrobienia. Odhaczone punkty wychodzą z niego do `SHIPPED.md`.
   - [ ] `SHIPPED.md`: obecna lista „New & fixed” z README, po wersji lub dacie, razem z historią zrobionych etapów przeniesioną z ROADMAP.
   - [ ] `README.md`: tylko najciekawsze rzeczy jako krótkie zajawki, zrzuty ekranu z iPhone'a i Maca, link do pełnej listy w `SHIPPED.md`. Sekcje Building, Contributing i Credits zostają.
   - [ ] Notatki z sesji (`VOICE_NOTES.md`, `MESSAGES_NOTES.md`) do katalogu `docs/`, a otwarte testy z nich jako punkty w ROADMAP.

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
   - [x] Usunięcie zakładki Powiadomienia (pokazuje tylko napis zastępczy, nie pobiera danych).
   - [x] Ustawienia jako zakładka skrajnie po prawej (bez przycisku „Done”, start na liście kategorii); zębatka znika z Profilu.
   - [x] Zakładki na nowym API `Tab` bez wymuszonego tła paska, więc pasek zakładek jest systemowym Liquid Glass; `TabView` nie siedzi już w `NavigationStack` (Home ma własny).
   - [x] Lista serwerów i lista kanałów na iPhonie przewijają się pod paskiem zakładek: lista serwerów to zwykły `ScrollView` z `.scrollEdgeEffectStyle(.soft)` zamiast własnej maski z zanikaniem (na macOS maska zostaje), a tło listy kanałów z zaokrąglonym rogiem sięga do dolnej krawędzi ekranu.
   - [x] Nowy układ zakładek na iPhonie: Home (tylko serwery), Messages, Search, Settings. Zakładka Profil usunięta: status, custom status, rich presence i „Konto od” są na stronie „Profile & Status” pod kartą profilu na górze Ustawień (jak karta Apple Account), konta w „My Account”, edycja w „Profiles”. Na macOS popover profilu zostaje.
   - [x] Messages: rozmowy prywatne i grupowe od najnowszych (nieprzeczytane, wzmianki, wyszukiwanie), znajomi (oczekujące, online z aktywnością, offline), nowa wiadomość z wyborem znajomego (`createDm`). Otwarcie rozmowy odznacza serwer, a powrót na Home przywraca ostatni serwer; ikonka DM zniknęła z listy serwerów na iPhonie.
   - [x] Inbox jako przełącznik „Mentions” w Messages zamiast osobnej zakładki: wzmianki i odpowiedzi ze wszystkich serwerów (nowy `getRecentMentions` w PaicordLib), z serwerem i kanałem, kropką nieprzeczytanych, filtrami „tylko odpowiedzi” i „bez @everyone/@here”, „Mark All as Read” i doładowywaniem starszych. Znajomi przeniesieni do arkusza pod przyciskiem w rogu (plakietka z zaproszeniami). Plakietka na zakładce Messages liczy nieprzeczytane DM-y; wzmianki z serwerów zostają w liście, bo potrafią iść w tysiące.
   - [x] Search jako własna funkcja, zakładka przed Ustawieniami: jedno pole szuka serwerów, kanałów, osób i wiadomości. Stuknięcie w serwer, kanał lub osobę zamienia je w token filtra (zawęża następne wyniki), strzałka otwiera. Serwery, kanały i osoby lokalnie i od razu (osoby na serwerze dociągane przez gateway op 8), wiadomości przez nowe `searchGuildMessages` / `searchChannelMessages` w PaicordLib z filtrem „zawiera” (link, obraz, plik…). Wiadomości wymagają serwera, kanału albo osoby z DM. Przy okazji: wartości w zapytaniach URL są poprawnie escapowane (`&`, `=`, `+`, `#`).
   - [x] Search: stuknięcie w wynik wiadomości otwiera kanał przewinięty do tej wiadomości i podświetla ją (gdy nie jest wczytana, czat wczytuje wiadomości wokół niej, a strzałka w dół wraca do najnowszych). Daty od–do jako `min_id`/`max_id` w zapytaniu do Discorda i regex po stronie aplikacji na wczytanych wynikach („Dates and Regex…” w menu filtrów i nad wynikami). Sprawdzone na NAScin na iOS i macOS. Szczegóły w `MESSAGES_NOTES.md`.
   - [x] Zaproszenia do znajomych: Messages → Friends ma zakładki Friends / Incoming / Sent z akceptacją, ignorowaniem przychodzących i anulowaniem wysłanych (za potwierdzeniem). Badge liczy przychodzące bez zignorowanych i oznaczonych jako spam; lista i badge zmieniają się na żywo z `RELATIONSHIP_ADD/UPDATE/REMOVE`. Prawdziwe konto nie ma zaproszeń: wygląd i ścieżka błędu sprawdzone na lokalnych danych testowych, prawdziwa akceptacja do sprawdzenia przez użytkownika.
   - [x] Foldery „Message Requests” i „Spam” w Messages (na Macu i iPadzie skróty nad listą DM-ów): podgląd pierwszej wiadomości, Accept / Ignore / Reject dla próśb, Not Spam / Delete dla spamu, Reject All / Delete All. W rozmowie z prośbą lub spamem zamiast pola wiadomości jest pasek z tymi wyborami. Nowe endpointy `acceptMessageRequest`, `rejectMessageRequest`, `batchRejectMessageRequests`, `getMessageRequestSupplementalData` w PaicordLib; `CurrentUserStore` obsługuje Channel Update kanałów prywatnych. Spam (2 prawdziwe wiadomości) tylko oglądany; akcje sprawdzone na lokalnych danych testowych (404 od Discorda na fałszywym kanale), prawdziwe do sprawdzenia przez użytkownika.
3. **Profil:**
   - [x] Działający wybór statusu (online, zaraz wracam, nie przeszkadzać, niewidoczny) przez `setPresence` i `modifyUserSettingsProto`; ten sam `ProfileButtonPopout` w arkuszu na iOS i w popoverze `ProfileBar` na macOS. Przy okazji naprawione: `modifyUserSettingsProto` w PaicordLib nie wysyłał treści zmiany, a `SettingsStore` ignorował częściowe aktualizacje ustawień z innych klientów.
   - [x] Podgląd i edycja custom statusu (emoji i tekst, „wyczyść po”). Czyszczenie zapisuje status z czasem wygaśnięcia „teraz”, bo serwer scala częściowe ustawienia i pusta wiadomość nie usunęłaby starego statusu. Emoji z serwera da się zachować, ale nie wybrać (pole przyjmuje emoji z klawiatury).
   - [x] „Konto od” (data z identyfikatora użytkownika) w zakładce Profil i w okienku profilu.
   - [x] Konta: lista z przełączaniem, „Dodaj konto”, „Wyloguj” (z potwierdzeniem; usuwa konto z pęku kluczy, token po stronie Discorda zostaje ważny).
   - [x] „Edytuj profil” jako link do `discord.com/settings/profiles` zamiast wyłączonego przycisku. Do sprawdzenia, czy Discord otwiera pod tym adresem właściwą stronę.
   - [x] Zakładka Profil jako natywna lista zamiast pustego ekranu: nagłówek (baner, awatar, nazwa, zaimki, odznaki) z dymkiem custom statusu, pod nim wybór statusu, „O mnie”, aktywność, połączone konta, „Konto od” i konta. Arkusz pod przyciskiem w rogu przestaje być potrzebny na iOS; popover na macOS zostaje.
   - [x] Własna aktywność (rich presence) jak w Serein `custom-rpc` / Vencord CustomRPC: typ (gra, słucha, ogląda, transmituje, rywalizuje), nazwa, dwie linie tekstu, ID aplikacji Discorda i obrazki (klucze zasobów albo adresy HTTPS), czas (od startu, odliczanie, od północy), rozmiar drużyny, dwa przyciski z linkami. Podgląd karty przed zastosowaniem, „Zastosuj” i „Zatrzymaj”. Aktywność idzie obok custom statusu w `setPresence` (gateway op 3) i wraca po ponownym połączeniu. Na iOS działa tylko, gdy aplikacja jest otwarta (w tle gateway się rozłącza); na macOS bez ograniczeń. Embedded App SDK z dokumentacji Discorda dotyczy aplikacji uruchamianych wewnątrz Discorda, więc tu się nie przyda.
   - [x] Przełącznik „Udostępniaj moją aktywność” (`status.showCurrentGame` w ustawieniach proto).
     Sekcje profilu (`CustomStatusRow`, `StatusSection`, `ActivitySection`, `AccountInfoSection`, `AccountsSection` w `ProfileBar.swift`) są wspólne dla zakładki na iPhonie i popovera na macOS. Rich presence: pola zapisywane per konto w `UserDefaults`, obrazki z linków idą przez nowy endpoint `createApplicationExternalAssets` w PaicordLib (`mp:` ścieżki), przyciski kodowane tak, jak oczekuje gateway kont użytkowników (`buttons` jako etykiety plus `metadata.button_urls`). Do sprawdzenia na żywo z prawdziwym ID aplikacji.
   - [x] ID aplikacji Discorda jako ustawienie w „My Account” (wspólne dla rich presence i przyszłych funkcji) ze sprawdzeniem przez publiczny `GET /applications/{id}/rpc` (nowy `getApplicationRPC` w PaicordLib, bez tokenu); po sprawdzeniu widać nazwę aplikacji. Przy okazji poprawiony adres `getPartialApplication` (`applications/{id}/public`, wcześniej 404).
   - [x] Natywna edycja profilu w Ustawienia → Profiles (i pod „Edit Profile”): profil główny (nazwa wyświetlana, zaimki, „O mnie”, awatar z `PhotosPicker` przycinany do 512 px) z podglądem, oraz profile per serwer (pseudonim, zaimki). W PaicordLib payloady `ModifyCurrentUser` i `ModifyCurrentMember` na pola kont użytkowników, z rozróżnieniem „nie wysyłaj” i `null`. Przetestowane na koncie: zaimki i pseudonim zapisane i przywrócone.
   - [x] fix: po rozwiązaniu captchy lub potwierdzeniu 2FA PaicordLib ponawiał żądanie z nagłówkami odpowiedzi Discorda zamiast z nagłówkami żądania, więc Discord zwracał 403. Dotyczyło też zwykłych ponowień po limicie zapytań.
   - [x] Połączone konta w Ustawienia → Connections: każde połączenie jako osobna sekcja z kafelkiem usługi (inicjał w kolorze marki), nazwą konta, nazwą usługi i znaczkiem weryfikacji; ostrzeżenie przy wygasłym (`revoked`). Przełączniki „Display on Profile” (`visibility`), „Display Details on Profile” (`metadata_visibility`, tylko gdy są metadane) i „Display as Status” (`show_activity`, dla Spotify, Xbox, PlayStation, Crunchyroll, Amazon Music, League of Legends i Riot Games) zmieniają się od razu i wracają do poprzedniej wartości, jeśli serwer odrzuci zmianę. „Remove” za potwierdzeniem. Nowe połączenie dodaje się przez discord.com/settings/connections otwierane w przeglądarce. Nowe endpointy `modifyOwnConnection` (`PATCH /users/@me/connections/{type}/{id}`) i `deleteOwnConnection` (`DELETE …`), payload `ModifyConnection`, pola `metadata`/`metadata_visibility` w `DiscordUser.Connection`; poprawione surowe wartości `Connection.Service` (były nazwami wyświetlanymi, np. `"GitHub"`, więc żadne prawdziwe połączenie się nie rozpoznawało) i dodane brakujące typy. Konto testowe nie ma połączeń: pusta lista sprawdzona na prawdziwym koncie, wygląd, przełącznik (404 i cofnięcie) oraz okno usuwania (anulowane) na tymczasowo wstrzykniętych danych.
   - [x] ~~Awatar, baner i „O mnie” per serwer~~: odrzucone. Wymagają Nitro, mało kto z nich skorzysta; payload już je obsługuje, więc da się je dopisać, gdyby były potrzebne.
4. **Ustawienia:**
   - [x] Sekcja „Paicord” → „O Aicord”: wersja, build, licencja GPL-3, link do repozytorium; bez „Made with ❤️ by llsc12”, naklejki z CDN Discorda i przycisku Donate. Na dole dopisek, że to fork Paicorda od llsc12.
   - [x] Moje konto: nagłówek z awatarem, e-mail (zamaskowany, odkrywany stuknięciem), 2FA, Nitro, „Konto od”, ID użytkownika do skopiowania; ta sama sekcja kont co w Profilu i sekcja aplikacji Discorda (Scan QR na iOS zostaje). Przełączanie kont resetuje też stan okien, jak w menu „Account”.
   - [x] Skróty klawiszowe: lista istniejących skrótów w stylu klawiszy (aplikacja, czat, przeglądarka multimediów); na macOS dodatkowo ⇧↩ i esc w czacie.
   - [x] Debug: bez przycisku podglądu okna sponsora.
   - [x] Puste sekcje („Coming Soon”) zostają jako miejsca na przyszłe ustawienia. Zostały już tylko Language i Voice & Video.
   - [x] Content & Social: media wrażliwe oraz przemoc (pokaż, rozmyj, zablokuj; osobno DM od znajomych, DM od innych, serwery), filtry słów (wulgaryzmy, treści seksualne, obelgi), filtr spamu w DM, DM od członków serwerów i prośby o wiadomość dla nowych serwerów, kto może zaprosić do znajomych. Wszystko w ustawieniach proto (`textAndImages`, `privacy`), wartości domyślne według docs.discord.food.
   - [x] fix: Discord zastępuje całą grupę ustawień proto, którą dostaje (`privacy`, `status`, `textAndImages`…), zamiast scalać pola. `patchUserSettings` wysyłał same zmienione pola, więc kasował resztę grupy (np. zmiana „Share My Activity” czyściła custom status). Teraz zmiana idzie na pełnej lokalnej kopii, a wysyłane są całe zmienione grupy; da się też zapisać `false` i zero.
   - [x] Media wrażliwe w Aicordzie: flagi skanu Discorda w PaicordLib (`Attachment.Flag` `containsExplicitMedia`, `containsGoreContent` itd., nowe `Embed.flags`), a w wiadomości rozmycie z „Show” albo blokada z notką, zależnie od ustawień i pochodzenia wiadomości (DM od znajomego, DM od innej osoby, serwer; własne wiadomości bez filtra). Nie przetestowane na prawdziwym oznaczonym obrazku; tabele flag pochodzą ze streszczenia docs.discord.food.
   - [x] Filtr słów w Aicordzie („Word Filter in Aicord”, lokalnie, nie na koncie): listy LDNOOBW (CC BY 4.0, 25 języków w `Resources/WordLists`, podziękowanie w „O Aicord”) plus własne słowa. Całe słowa bez wielkości liter i znaków diakrytycznych, frazy, podciągi dla japońskiego, chińskiego i tajskiego. Zakres: DM od osób spoza znajomych albo wszystko. Trafiona wiadomość zwija się do „Hidden by your word filter · Show”.
   - [x] Filtr słów także w cytatach odpowiedzi, we wzmiankach (Messages → Mentions) i w wynikach Search: zamiast tekstu „Hidden by your word filter”.
   - [x] ~~Odmiana w filtrze słów~~ i ~~filtry słów z konta Discorda w Aicordzie~~: odrzucone. Dopasowanie po początku słowa daje fałszywe trafienia, a na braki jest pole „Your Own Words”; listy Discorda nie znamy, a lista społeczności spełnia tę rolę.
   - [x] Data & Privacy: prywatność aktywności (udostępnianie aktywności, domyślne udostępnianie w nowych serwerach z polem v1 i v2, dołączanie bez prośby dla znajomych i osób z kanału głosowego, ostatnie gry na profilu), użycie danych (misje z danymi zewnętrznymi, wykrywanie czytnika ekranu, pomoc filtrowi spamu) w ustawieniach proto (`privacy`, `status`). Zgody „usage_statistics” i „personalization” przez REST `/users/@me/consent`, stan ostatniej prośby o dane i przycisk „Request a Copy of Your Data” przez `/users/@me/harvest` (nowe endpointy i modele w PaicordLib). Zapis sprawdzony w symulatorze z ponownym uruchomieniem; samej prośby o dane nie wysyłano z prawdziwego konta.
   - [x] Data & Privacy: pominięte świadomie synchronizacja kontaktów, wykrywanie kont Steam/Blizzard, drops i ustawienia Game SDK. Wyjątki per serwer przeniesione do „Ustawień serwera” (część 6).
   - [x] Usunięcie sekcji Family Centre (kontrola rodzicielska Discorda: łączenie konta nastolatka z kontem rodzica i cotygodniowe raporty aktywności). Rodzic i tak użyje oficjalnej aplikacji, a funkcja wymaga słabo opisanych endpointów na kontach dzieci, więc w Aicordzie jej nie będzie.
   - [x] Usunięcie sekcji Clips (nagrywanie fragmentów gier w aplikacji desktopowej Discorda); Aicord nie nagrywa gier, więc nie ma tu czego ustawiać.
   - [x] Scan QR Code na iOS: kamera na cały ekran zamiast okienka w wierszu formularza, z ramką celownika i podpowiedzią, ciemny ekran bez paska zakładek. Po zeskanowaniu niepasującego kodu skaner startuje od nowa (wcześniej stawał), a bez zgody na kamerę jest ekran z „Open Settings” zamiast czarnego tła. Sprawdzone na iPhonie: cały flow od zeskanowania do zalogowania.
   - [x] Grupy w Ustawieniach: „User Settings” nazywa się „Discord Settings” (wszystko zapisuje się na koncie Discorda), a „App Settings” to „Aicord Settings” (ustawienia samej aplikacji). Osobna grupa „Aicord” zniknęła, „About Aicord” jest na dole „Aicord Settings”.
   - [x] Authorised Apps: lista aplikacji OAuth2 z dostępem do konta (boty, strony logujące przez Discorda) z ikoną, nazwą, znaczkiem „Bot”, opisem i uprawnieniami opisanymi zwykłymi słowami (nieznane zakresy pod surową nazwą). Cofanie dostępu („Deauthorise”: przesunięcie na iOS, menu kontekstowe) za potwierdzeniem. Nowe endpointy `listOAuth2Tokens` (`GET /oauth2/tokens`) i `revokeOAuth2Token` (`DELETE /oauth2/tokens/{id}`) oraz model `OAuth2Authorization` w PaicordLib. Lista sprawdzona w symulatorze na prawdziwym koncie; okno potwierdzenia otwarte i anulowane, żadnej aplikacji nie cofnięto.
   - [x] ~~Authorised Apps: ujawnienia (`disclosures`), historia upoważnień jednej aplikacji, linki do regulaminu i polityki prywatności~~: odrzucone, lista z odbieraniem dostępu wystarczy.
   - [x] Devices: lista sesji, na których konto jest zalogowane (system z ikoną, klient, przybliżona lokalizacja, „Last used …” względnie), od ostatnio używanej. Bieżąca sesja Aicorda osobno jako „This Device”, rozpoznana po `auth_session_id_hash` z READY (i `AUTH_SESSION_CHANGE`), bez możliwości wylogowania stąd. Wylogowanie pojedynczego urządzenia (przesunięcie na iOS, menu kontekstowe) i „Log Out All Known Devices” za potwierdzeniem; ewentualne MFA obsługuje istniejące ponowienie z `X-Discord-MFA-Authorization`. Endpointy `getAuthSessions`/`logoutAuthSessions` już były w PaicordLib; doszło pole `auth_session_id_hash` w `Gateway.Ready` i `AuthSessionChange`. Lista sprawdzona w symulatorze na prawdziwym koncie; żadnej sesji nie wylogowano.
   - [x] Appearance: jedna sekcja zamiast Theming, Appearance i pustej Accessibility. Wygląd Light / Dark / Automatic (to trzy wbudowane motywy, więc zapisany wybór zostaje; kolor schematu ustawiany też na oknie, bo `preferredColorScheme(nil)` nie zawsze cofa wymuszony), kolor akcentu (kolor motywu, osiem gotowych i dowolny z próbnika „Custom Color”; zmienia akcent, główne przyciski i ikony w Ustawieniach) z przełącznikiem „Accent on Tab Bar and Icons” (zaznaczona karta, przyciski paska narzędzi, ikony paska wpisywania zamiast szarości), własne motywy JSON na osobnej stronie. Tekst: rozmiar przez Dynamic Type albo systemowy, krój System / Rounded / Serif / Monospaced (`fontDesign`, działa z semantycznymi stylami). Ruch: własne „Reduce Motion” razem z systemowym (bez animacji SwiftUI w całej aplikacji, nieruchome naklejki) i „Animate New Messages” (dawne „Animate Chat Messages”: nowe i wysyłane wiadomości wsuwają się zamiast pojawiać od razu). Z konta Discorda (`textAndImages`): animowane emoji, autoodtwarzanie GIF-ów (wyłączone: pierwsza klatka z plakietką GIF, odtwarzanie w podglądzie albo po najechaniu na Macu), animacja naklejek Always / On Interaction / Never i plakietka ALT z opisem obrazu. „Display zoom” pominięty: na iOS robiłby to samo co rozmiar tekstu. Klucze `UserDefaults` pod `Paicord.Appearance.*`. Przy okazji naprawiony odczyt kolorów z JSON (`Scanner` stawał na „#” i każdy kolor wychodził przezroczysty), przez co importowane motywy nie mogły działać.
   - [x] Chat, etap 1: ustawienia z konta Discorda (`textAndImages`), działające też w oficjalnych aplikacjach. „Show Reactions” (`renderReactions`), „Show Link Previews” (`renderEmbeds`: bez embedów, a link z samym obrazkiem znów widać jako tekst), „Show Uploaded Images and Videos” (`inlineAttachmentMedia`: obrazy i filmy jako wiersze plików z ikoną, otwierane w przeglądarce multimediów), „Show Media from Links” (`inlineEmbedMedia`: bez embedów typu image / gifv / video). „Show Spoilers” On Tap / On Servers I Moderate (uprawnienie Manage Messages) / Always (`renderSpoilers`) dla `||tekstu||` i załączników-spoilerów (flaga `isSpoiler` albo nazwa `SPOILER_…`), które wcześniej nie były zakryte wcale; zakrywa je ta sama zasłona co wrażliwe media. „Convert Emoticons to Emoji” (`convertEmoticons`, domyślnie włączone jak w Discordzie): przy wysyłaniu i edycji `:)` → 🙂, `<3` → ❤️ itd., tylko osobne słowa, nigdy w kodzie ani w linkach. Przy okazji: odpowiedź serwera albo echo z gatewaya po starszym zapisie ustawień nie cofa już nowszej zmiany (szybkie przełączanie kilku przełączników gubiło część z nich).
   - [x] Chat, etap 2: picker emoji (pole wiadomości i reakcje, iOS i macOS) pokazuje tylko to, czego konto może użyć. Bez Nitro: emoji Unicode i nieanimowane emoji serwera, na którym jesteś (w DM same Unicode). Emoji ograniczone do ról, których nie masz, znikają zawsze, także z Nitro. Serwer, na którym jesteś, jest pierwszy na liście. Lokalny przełącznik „Show Emoji That Need Nitro” (`Paicord.Chat.ShowsNitroEmoji`, widoczny tylko bez Nitro) pokazuje resztę wyszarzoną, z kłódką i podpisem „Requires Nitro”; nie da się ich wybrać, bo Discord i tak by je odrzucił. To samo dotyczy ulubionych, często używanych i wyszukiwania.
   - [x] Chat, etap 3: „Show Hidden Channels” (lokalnie, `Paicord.Chat.ShowsHiddenChannels`, jak ShowHiddenChannels z Vencorda). Kanały serwera bez uprawnienia View Channel (i kategorie z samymi takimi kanałami) pojawiają się na liście wyszarzone, z kłódką i bez wskaźników nieprzeczytanych. Stuknięcie otwiera arkusz (na Macu popover) z nazwą, tematem i tym, kto ma dostęp: role z nakładką pozwalającą widzieć kanał (bez @everyone, w kolorach ról) i liczba osób dodanych z nazwy, albo „osoby ze specjalnymi uprawnieniami”, gdy dostęp daje np. Administrator. Wszystko z danych, które gateway już przysyła; wiadomości nie da się czytać. Sprawdzone na FashionReps, Laczowice i KravaSign.
   - [x] Chat, etap 4: „Message Logging” (lokalnie, domyślnie wyłączone, wzorowane na message-delete-protector z Serein). „Keep Deleted Messages” (`Paicord.Chat.KeepsDeletedMessages`): cudza wiadomość usunięta, gdy była wczytana (także usuwanie wielu naraz), zostaje w czacie z czerwonym tłem i paskiem, etykietą „Deleted” i przyciskiem „Hide”; menu kontekstowe ma wtedy tylko „Copy Text” i „Hide Deleted Message”. Twoje własne usunięcia znikają jak zwykle. „Keep Edit History” (`Paicord.Chat.KeepsEditHistory`): poprzednia treść edytowanej wiadomości przekreślona pod nią, od najstarszej. Oba trzymane tylko w pamięci `ChannelStore` (nic na dysku), znikają po zamknięciu aplikacji, a wyłączenie przełącznika od razu czyści je we wszystkich otwartych kanałach. Przy okazji: „Edit Message” w menu wiadomości na iOS nic nie robiło (pusta akcja), teraz otwiera edycję jak na Macu.
   - [x] Chat, etap 5: „Message Display” Cozy / Compact (`messageDisplayCompact`, z konta Discorda, jak w oficjalnych aplikacjach). Compact: bez awatarów, godzina w kolumnie awatara (pełna data w podpowiedzi), nick i treść w jednej linii, kolejne wiadomości z grupy bez nicku i z ukrytą godziną, mniejsze odstępy między grupami; odpowiedzi, „(edited)”, historia edycji i usunięte wiadomości działają jak w Cozy. Sekcja Chat jest tym samym gotowa; Voice & Video zostaje na osobny etap.
   - [x] Notifications: lokalne powiadomienia z gatewaya (`NotificationStore`, `UNUserNotificationCenter`), bez serwera push. Na macOS działają w tle; na iOS gdy Aicord jest otwarty i ok. 30 s po wyjściu (`beginBackgroundTask`), potem iOS usypia aplikację. Na górze sekcji status zgody, „Allow Notifications”, „Open Settings” i „Send Test Notification”. Alerts: włącznik, „Show While Using Aicord”, podgląd (imię i treść / samo imię / ukryty), dźwięk, badge na ikonie (wyłączony / nieprzeczytane DM / DM i wzmianki, bez wyciszonych). Direct Messages: Everyone / Friends / Only Selected People / Everyone Except z listą osób (przyjaciele i DM), lokalnie; DM wyciszone w Discordzie zawsze milczą. Servers: reguły Discorda (`user_guild_settings`: poziom kanału, kategorii, serwera i domyślny serwera, `suppress_everyone`/`suppress_roles`, wyciszenia z czasem końca; wyciszone przepuszczają tylko wzmianki o Tobie i Twoich rolach), do tego „Only Selected” (lokalna biała lista serwerów i kanałów) albo „All Except” (czarna lista = poziom „Nothing” zapisany na koncie przez nowe `modifyUserGuildSettings`, `PATCH /users/@me/guilds/{id}/settings`, z zapamiętaniem poprzedniego poziomu do przywrócenia). Przełączniki @everyone/@here i wzmianek ról, słowa kluczowe działające jak wzmianka. Quiet: godziny ciszy i status „Nie przeszkadzać” (powiadomienie trafia do listy bez banera i dźwięku). Other: zaproszenia do znajomych. Pomijane: własne wiadomości, `@silent`, zablokowani, filtr słów, kanał, który właśnie oglądasz. Akcje „Reply” i „Mark as Read”, stuknięcie otwiera kanał (na iPhonie także z karty Settings), przeczytanie kanału zdejmuje jego powiadomienia. `UserGuildSettingsStore` obsługuje teraz `USER_GUILD_SETTINGS_UPDATE`, a `ReadStateStore` liczy nowe wiadomości w DM (badge Messages nie rósł na żywo). Klucze `Paicord.Notifications.*`. Sprawdzone w symulatorze: zgoda, testowe i prawdziwe powiadomienie z serwera, listy. Nie sprawdzone: zapis „Nothing” na koncie (wymaga zgody), akcje Reply/Mark as Read i stuknięcie w prawdziwe powiadomienie, macOS poza buildem.
   - [x] Advanced zamiast pustej strony, a osobna sekcja Debug usunięta (z nią przycisk „Force fallback account switcher”). „Developer Mode” (`appearance.developerMode` z konta Discorda): „Copy Message ID” i „Copy Author ID” już od niego zależały, teraz też „Copy User ID” i „Copy Server ID”, które wcześniej były zawsze widoczne. Storage: rozmiar cache obrazków liczony z plików na dysku (`URLCache.currentDiskUsage` po czyszczeniu dalej podaje stary rozmiar) i „Clear Cache” (dysk i pamięć). Diagnostics: „View Logs” przeniesione z Debug i „Share Logs” jako tekst. Language zostaje na później.
   - [ ] Language: na koniec, po pozostałych poprawkach. Voice & Video powstaje razem z Etapem 9 (wybór urządzeń, push-to-talk, wyciszenie).
   - Nie robimy: powiadomień push na iOS, gdy Aicord jest zamknięty. Wymagałyby własnego serwera trzymającego token konta i połączenie z gatewayem; zostają lokalne powiadomienia z działającej aplikacji.
5. **Pozostałości po Paicordzie poza Ustawieniami:**
   - [x] Usunięcie `SponsorSheet` (samo wyskakuje po 2 dniach z linkiem do sponsorowania llsc12).
   - [x] Usunięcie `UpdateCheck` i `SUFeedURL` (czyta kanał wydań llsc12, więc proponowałby pobranie oryginalnego Paicorda); razem z resztą kluczy Sparkle w `Info.plist`.
   - [x] „Aicord” zamiast „Paicord” na ekranie łączenia (bez „SwiftUI ftw”), w tekście przy kodzie QR logowania, w tytule okna logów i jako autor wbudowanych motywów.
   - [x] Nazwa wyświetlana aplikacji „Aicord” (`CFBundleDisplayName`: ekran główny iOS). Menu i Dock na macOS biorą nazwę z `PRODUCT_NAME`, więc zmienią się dopiero razem z targetem (Etap 5.4). Klucze `UserDefaults` i wewnętrzne linki `paicord://` zostają.
   - [x] Opisy uprawnień (aparat, mikrofon, ruch, rozpoznawanie mowy) zamiast żartobliwych tekstów.
   - [x] Usunięcie `.github/FUNDING.yml` (przycisk Sponsor prowadził do llsc12) oraz workflowów `build.yml` i `release_pr.yml` (podpisywanie, Sparkle i webhooki Discorda na sekretach llsc12). `build_pr.yml` zostaje jako budowanie PR-ów bez podpisu.
   - [x] Usunięcie z `Localizable.xcstrings` tekstów po usuniętych ekranach.
   - [x] Usługa w pęku kluczy `net.smigi.aicord.Accounts` (zamiast `com.llsc12.Paicord.Accounts`) i katalog cache obrazków `net.smigi.aicord.imagecache`. Wymaga ponownego zalogowania; stary wpis `com.llsc12.Paicord.Accounts` można usunąć w Pęku kluczy.
6. **Lista kanałów:**
   - [x] Kategorie domyślnie rozwinięte; zapamiętywane są tylko te zwinięte przez użytkownika (nowy klucz `GuildCategory.<id>.Collapsed`, więc stare stany „zwinięte” się nie przenoszą).
   - [x] Nagłówek kategorii w stylu nagłówków list Apple: wersaliki, `footnote` semibold, szewron po prawej obracany przy zwijaniu, cienka linia między kategoriami (bez linii nad pierwszą widoczną pozycją). Czcionka w całej aplikacji to systemowy SF Pro.
   - [x] Kanały forum, multimediów i sceny z własną ikoną zamiast surowej nazwy typu („guildForum”) pod nazwą kanału.

7. **Weryfikacja:**
   - [x] Build macOS (arm64) i iOS bez nowych ostrzeżeń, zrzuty ekranu z obu platform.
   - [x] Poprawki po przeglądzie macOS: okno Ustawień startuje w rozmiarze 860×620, a pasek boczny ma co najmniej 210 pt (nazwy sekcji nie są ucinane; `navigationSplitViewColumnWidth` musi stać za `.searchable`); popover profilu ma 340×560 pt, przełącznik „Share My Activity” jako switch, „Log Out” na czerwono.

8. **Poprawki interfejsu (po Ustawieniach):**
   - [x] iPhone startuje na Home zamiast na pustym ekranie czatu „:3 Select a channel to start chatting” (`chatOpen` domyślnie `false`); dopóki nie wybrano kanału, czatu nie da się wysunąć gestem.
   - [x] Kontener kanałów na Home: tło kończyło się nad paskiem zakładek (widać to było tylko w ciemnym motywie), teraz sięga pod pasek jak lista.
   - [x] Menu wiadomości od nowa (przytrzymanie na iOS, prawy przycisk na Macu). Na górze rząd szybkich reakcji (`ControlGroup` w stylu `.palette`, przy uprawnieniu `addReactions`): 5 emoji unicode z ulubionych, potem z najczęściej używanych w reakcjach i ogólnie (`frecencySettings`), uzupełnione domyślnymi 👍 ❤️ 😂 😮 😢, oraz „Add Reaction”, które otwiera picker. Wysyłanie reakcji jest wspólne z pickerem (`ReactionPickerTarget.react`). Dalej grupy: Reply, Edit Message, Mention; Copy Text, Copy Message Link (oraz Copy Message ID i Copy Author ID w Developer Mode); Mark Unread; Delete Message (na iOS z potwierdzeniem). „Mark Unread” działa: ack z ID o jeden mniejszym i `manual: true`, a czat nie oznacza kanału jako przeczytanego, dopóki go nie opuścisz (`ReadStateStore.manuallyUnread`). Usunięte: puste „Apps”, „Thread” (Aicord nie ma widoku wątków) i „Forward” (brak wyboru kanału docelowego i wyświetlania przekazanych wiadomości, czyli `message_snapshots`; osobne zadanie). Podgląd na iOS zostaje domyślny (uniesiona komórka).
   - [x] Forward: „Forward” w menu wiadomości otwiera wybór do pięciu celów (DM-y, grupy, kanały serwerów) z wyszukiwaniem i opcjonalnym komentarzem (wysyłanym jako osobna wiadomość). Wysyłka przez `message_reference` typu `forward`; przekazane wiadomości mają „Forwarded” i źródło (kanał, serwer, data), które otwiera oryginał. Sprawdzone z NAScin na NAScin w symulatorze; nie sprawdzone: forward do DM, kilka celów naraz, wysyłka z Maca.
   - [x] Menu serwera i kanału (przytrzymanie, prawy przycisk na Macu): „Mark as Read” (serwer jednym `POST /read-states/ack-bulk`, nowy endpoint `bulkAckReadStates`), „Pin to Top” (lokalnie w Aicord, `PinnedPlacesStore`: przypięte serwery nad folderami, kanały nad listą swojego serwera), „Mute” na 15 min, 1 h, 8 h, 24 h lub do odwołania (doszło `mute_config` w `ModifyUserGuildSettings`) i „Notify” (All Messages / Only @mentions / Nothing, przy kanale też „Use Server Default”; przy serwerze przełączniki @everyone/@here i wzmianek ról). Mute i Notify zapisywane na koncie przez `UserGuildSettingsStore`. Z menu serwera arkusz „Server Settings” (`ServerSettingsSheet`): powiadomienia i wyciszenie, wyjątki per serwer z Content & Social (`restrictedGuildIds`, `messageRequestRestrictedGuildIds`) i Data & Privacy (`activityRestrictedGuildIds`, `activityJoiningRestrictedGuildIds`) zapisywane przez `patchUserSettings`, oraz link do istniejącego edytora profilu serwera. Menu, przypinanie i arkusz sprawdzone w symulatorze; ustawień konta na prawdziwych serwerach nie zmieniano.
   - [ ] Purge: usuwanie własnych wiadomości z czatu (z ostatnich X minut albo wszystkich), powoli, z potwierdzeniem i postępem. Cudzych wiadomości w DM API Discorda nie pozwala usunąć, a masowe usuwanie z konta użytkownika to ryzyko blokady.
   - [ ] Rozszerzenie Safari: linki zaproszeń `discord.gg/…` i `discord.com/invite/…` otwierane w Aicord przez własny schemat URL (Universal Links dla discord.com należą do Discorda). Osobny target, włączany przez użytkownika w ustawieniach Safari.

---

### 🧪 Etap 9: Voice — kanały głosowe i rozmowy w DM
Startujemy po odświeżeniu UI. To port, nie merge. Bazą kodu jest gałąź [`upstream/voice`](https://github.com/llsc12/Paicord/tree/voice): działający szkic w Swifcie (dźwięk w obie strony, DAVE przez DaveKit, rozmowy w DM z dzwonieniem), ale odstaje o 126 commitów od upstream `main` i stoi na usuniętym w Etapie 5 stosie NIO. Wzorcem zachowania jest [Serein](https://github.com/ViceVerse-cz/Serein) (Rust, MIT/Apache, więc wolno adaptować do GPL-3): `crates/discord-voice/README.md`, `docs/voice.md`, `transport.rs` i `crypto.rs`. Jego DAVE (`davey`/OpenMLS) i audio (CPAL, Sonora, RNNoise) nie nadają się dla Swifta, więc bierzemy z niego zachowanie, nie kod.
1. **Modele (`DiscordModels`):**
   - [x] Przeniesienie z gałęzi voice `VoiceGateway.swift`, `VoiceGateway+Payloads.swift` i `RTP/` (RTP, RTCP, RTPType) oraz zmian voice-state w `Gateway.swift`, `Guild.swift` i `Voice.swift`. `ByteBuffer` → `Data`.
2. **Transport (`DiscordVoice`, bez NIO, AsyncHTTPClient, WSClient i Atomics):**
   - [x] WebSocket voice v8 na `URLSessionWebSocketTask`, jak w `UserGatewayManager`; UDP na Network.framework (`NWConnection`).
   - [x] Maszyna stanów jak w Serein: Resume z `seq_ack`, jeden niepotwierdzony heartbeat dozwolony, po drugim resume; najwyżej dwa resume z rzędu, potem ponowne dołączenie.
   - [x] Limity czasu: połączenie 15 s, UDP discovery 8 s, negocjacja DAVE 90 s (30 s dla kolejnego przejścia); UDP keepalive.
   - [x] Adresy UDP tylko publiczne i tylko te podane przez serwer; host WebSocket tylko z domen mediów Discorda.
3. **Szyfrowanie transportu (CryptoKit, bez swift-crypto):**
   - [x] `aead_aes256_gcm_rtpsize` (preferowany) przez `AES.GCM`.
   - [x] `aead_xchacha20_poly1305_rtpsize` (wymagany przez Discorda) jako własne HChaCha20 plus `ChaChaPoly` z CryptoKit.
   - [x] Testy z wektorami testowymi dla obu trybów rtpsize.
4. **DAVE (E2EE):**
   - [x] `llsc12/DaveKit` (oficjalny libdave przez C++ interop), przypięty do konkretnego commitu. `.interoperabilityMode(.Cxx)` tylko w targecie `DiscordVoice`; sprawdzić, czy nie psuje Swift 6 language mode w innych targetach. Psuł: importujący muszą dostać `-disable-cxx-interop-requirement-at-import`, szczegóły w `VOICE_NOTES.md`.
   - [x] Zabezpieczenia z Serein: odrzucanie nieoczekiwanego ID grupy, użytkowników spoza listy uczestników, duplikatów i propozycji innych niż Add/Remove.
   - [x] Odzyskiwanie przy nieprawidłowej grupie; żadnych mediów przed zakończeniem przejścia; logi bez sekretów.
5. **Audio i aplikacja:**
   - [x] `VoiceConnectionStore.swift` z gałęzi voice: AVAudioEngine z voice processing (redukcja echa i szumu z systemu zamiast Sonora/RNNoise), Opus przez `swift-opus`.
   - [x] Jitter buffer i PLC jak w Serein: 8 pakietów na mówcę, start po 40 ms, najwyżej 3 pakiety PLC.
   - [x] `VoiceChannelsStore.swift`, `PCMFloatRingBuffer.swift`, uczestnicy kanałów głosowych w liście kanałów. Inaczej niż na gałęzi: uczestnicy z `GuildStore.voiceStates` (`VoiceChannelButton`), bufor i mikser w `DiscordVoice`.
   - [x] UI: `VoiceView`, `CallView` i pasek rozmowy w `ProfileBar`, dopasowane do Liquid Glass i obecnej nawigacji. Zamiast osobnych widoków: `VoiceCallBar` nad `ProfileBar`, akcesorium paska kart na iPhonie i przycisk połączenia w nagłówku DM.
   - [x] Wyciszenie, wyłączenie dźwięku, wybór urządzeń wejścia i wyjścia, push-to-talk. Ich ustawienia trafiają do pustej dziś strony Settings → Voice & Video.
   - [x] Nie przenosimy usunięć z gałęzi voice (`DiscordCache`, `GatewayEventHandler`, `BotAuthManager`), zmian nawigacji w `PaicordAppState` ani starych zależności.
6. **Weryfikacja:**
   - [x] PaicordLib i aplikacja (macOS, arm64) się budują, testy przechodzą.
   - [ ] Ręczny test na koncie (zrobione: dołączenie do pustego kanału serwera i wyjście, z DAVE v1, na symulatorze iOS; zostaje test z drugą osobą, patrz `VOICE_NOTES.md`): dźwięk w obie strony z DAVE w DM, w rozmowie grupowej i na kanale serwera; dołączanie i wychodzenie uczestników; wznowienie po zerwaniu sieci.
7. **Później:**
   - [ ] Wideo i udostępnianie ekranu. Serein ma do tego ścieżki na macOS (ScreenCaptureKit, VideoToolbox).

---

### 🔜 Etap 10: Intelligence — tłumaczenie i podsumowania

Po Etapie 7 (odchudzenie biblioteki) i po scaleniu zestawu Messages (Forward zmienia to samo menu wiadomości). Działa na iOS i macOS, na obecnym targecie.

1. **Sekcja ustawień „Intelligence” (Aicord Settings):**
   - [ ] Dostawca: na urządzeniu (Foundation Models / Apple Intelligence, z kontrolą dostępności urządzenia i regionu) albo API zgodne z OpenAI (adres, klucz w pęku kluczy, model, „Test Connection”). Pasuje też lokalny serwer (Ollama, LM Studio).
   - [ ] Prywatność: domyślnie tylko na urządzeniu; zewnętrzne API wyłączone, dopóki ktoś go nie skonfiguruje; przy każdej funkcji informacja, dokąd idą dane; osobny przełącznik dla DM, domyślnie wyłączony.
2. **Tłumaczenie:**
   - [ ] Framework Translation zamiast modelu językowego (na urządzeniu, bez klucza). „Translate” w menu wiadomości, tłumaczenie pod treścią z możliwością cofnięcia.
   - [ ] Język docelowy i automatyczne tłumaczenie wybranych języków.
3. **Podsumowania kanału:**
   - [ ] „Summarize” w nagłówku kanału: nieprzeczytane albo ostatnie 100 / 500 / 1000 wiadomości. Wynik w arkuszu, punkty z linkami do wiadomości.
   - [ ] Na urządzeniu okno kontekstu to ok. 4 tys. tokenów: podsumowanie etapami (kawałki, potem podsumowanie podsumowań), z postępem. Przez API całość jednym zapytaniem, gdy się mieści.
4. **Czytanie i nadrabianie:**
   - [ ] „Co mnie ominęło”: wszystkie nieprzeczytane kanały naraz jako jedna lista (serwer → kanał → 2–3 punkty).
   - [ ] Podsumowanie wątku albo łańcucha odpowiedzi od wybranej wiadomości w górę.
   - [ ] „Wyjaśnij”: slang, skróty i żargon serwera (np. W2C, QC) z kontekstem kilku wcześniejszych wiadomości.
5. **Wyszukiwanie:**
   - [ ] Wyszukiwanie w języku naturalnym w Search: zdanie („kto polecał agenta do wysyłki w zeszłym tygodniu”) zamienione na filtry (autor, kanał, daty, „zawiera link”), wyniki ułożone od najtrafniejszych.
   - [ ] Pytanie do kanału („jaki jest regulamin aukcji?”): odpowiedź z linkami do wiadomości źródłowych, na przypiętych i ostatnich wiadomościach.
6. **Porządek i bezpieczeństwo:**
   - [ ] Inteligentne powiadomienia: lokalny model ocenia, czy wiadomość z wyciszonego kanału jest dla Ciebie ważna (pytanie do Ciebie, Twoje tematy), i wtedy powiadamia mimo wyciszenia. Rozszerza sekcję Notifications.
   - [ ] Ostrzeżenie przed oszustwem w DM od nieznajomych: fałszywe Nitro, „przypadkowe zgłoszenie konta”, linki phishingowe. Na urządzeniu, uzupełnia filtr spamu z Content & Social.
   - [ ] Opisy obrazów bez tekstu alternatywnego (także dla VoiceOver): tekst z obrazka przez Vision (OCR) na urządzeniu, pełny opis przez API, jeśli model widzi obrazy (Foundation Models ich nie obsługuje).
7. **Granice:**
   - [ ] Tylko czytanie: Intelligence niczego nie wysyła do Discorda (bez automatycznych odpowiedzi), więc nie jest automatyzacją konta.
   - Nie robimy: pomocy w pisaniu (poprawianie, ton, tłumaczenie szkicu), bo daje ją już system (Writing Tools w iOS i macOS).

---

### 🔜 Etap 11: Aicord dla macOS

Aicord na Macu to już natywna aplikacja (jeden wieloplatformowy target SwiftUI, nie Mac Catalyst), ale dzieli szkielet `LargeBaseplate` z iPadem i przez to wygląda jak aplikacja na iPada. Po Etapie 7 i zmianie nazw targetów (Etap 5.4), żeby przebudowywać targety i `pbxproj` tylko raz.

1. **Interfejs Maca:**
   - [ ] Własny szkielet `MacBaseplate` zamiast wspólnego z iPadem: pasek boczny serwerów i kanałów w stylu systemowym, paski narzędzi, inspektor członków.
   - [ ] Menu aplikacji, skróty, wiele okien (kanał w osobnym oknie), Ustawienia jako systemowe okno `Settings`.
2. **Serwer MCP (połączenie Claude z Discordem):**
   - [ ] Mały pomocniczy program (target command-line) rozmawiający przez stdio i przekazujący zapytania do działającej aplikacji Aicord; aplikacja główna zostaje jedna.
   - [ ] Domyślnie tylko odczyt (kanały, wiadomości, wyszukiwanie, podsumowania). Wysyłanie najwyżej z potwierdzeniem każdej akcji w aplikacji: działanie przez token użytkownika to automatyzacja konta, której Discord zabrania (self-bot), więc ryzyko blokady trzeba ograniczyć.

---

### 🔜 Etap 12: Wydania — macOS i iOS w GitHub Releases

Na końcu, gdy aplikacja jest stabilna. Wydanie budowane przez GitHub Actions z tagu `v*` (dziś jest tylko `build_pr.yml`, bez podpisu).

1. **macOS: podpisana aplikacja z aktualizacjami:**
   - [ ] Podpis Developer ID i notaryzacja (wymaga płatnego konta Apple Developer). Certyfikat i klucz API App Store Connect jako sekrety repozytorium, `.app` w `.zip` albo `.dmg` w Releases.
   - [ ] Powiadomienie o aktualizacji. Do wyboru: Sparkle 2 z własnym appcastem i kluczem EdDSA (w Etapie 1 usunięty razem z kanałem llsc12; pobiera i instaluje sam) albo lekkie sprawdzanie najnowszego wydania przez API GitHuba z linkiem do pobrania. Wyłącznik w Settings → Advanced.
2. **iOS: niepodpisana `.ipa` i źródło AltStore:**
   - [ ] Build bez podpisu (`CODE_SIGNING_ALLOWED=NO`), `Payload/Aicord.app` spakowane do `.ipa` w Releases.
   - [ ] Repozytorium AltStore (działa też w SideStore): plik źródła JSON (nazwa, ikona, opis, wersje z linkami do `.ipa`, uprawnienia) generowany przez workflow przy każdym wydaniu i publikowany np. na GitHub Pages.
   - [ ] Sprawdzić uprawnienia i rozszerzenia pod darmowe konto: AltStore podpisuje kontem użytkownika, a darmowe konto ma limit 3 App ID, więc każde rozszerzenie (np. Safari z Etapu 8) zjada jedno miejsce. Push i inne uprawnienia płatnego konta nie zadziałają.
3. **Opis wydań:**
   - [ ] Notatki do wydania z `SHIPPED.md` (Etap 6.4), link do źródła AltStore i instrukcja instalacji w README.
