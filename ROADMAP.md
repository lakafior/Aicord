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
   - [x] Usunięcie zakładki Powiadomienia (pokazuje tylko napis zastępczy, nie pobiera danych).
   - [x] Ustawienia jako zakładka skrajnie po prawej (bez przycisku „Done”, start na liście kategorii); zębatka znika z Profilu.
   - [x] Zakładki na nowym API `Tab` bez wymuszonego tła paska, więc pasek zakładek jest systemowym Liquid Glass; `TabView` nie siedzi już w `NavigationStack` (Home ma własny).
   - [x] Lista serwerów i lista kanałów na iPhonie przewijają się pod paskiem zakładek: lista serwerów to zwykły `ScrollView` z `.scrollEdgeEffectStyle(.soft)` zamiast własnej maski z zanikaniem (na macOS maska zostaje), a tło listy kanałów z zaokrąglonym rogiem sięga do dolnej krawędzi ekranu.
   - [x] Nowy układ zakładek na iPhonie: Home (tylko serwery), Messages, Search, Settings. Zakładka Profil usunięta: status, custom status, rich presence i „Konto od” są na stronie „Profile & Status” pod kartą profilu na górze Ustawień (jak karta Apple Account), konta w „My Account”, edycja w „Profiles”. Na macOS popover profilu zostaje.
   - [x] Messages: rozmowy prywatne i grupowe od najnowszych (nieprzeczytane, wzmianki, wyszukiwanie), znajomi (oczekujące, online z aktywnością, offline), nowa wiadomość z wyborem znajomego (`createDm`). Otwarcie rozmowy odznacza serwer, a powrót na Home przywraca ostatni serwer; ikonka DM zniknęła z listy serwerów na iPhonie.
   - [x] Inbox jako przełącznik „Mentions” w Messages zamiast osobnej zakładki: wzmianki i odpowiedzi ze wszystkich serwerów (nowy `getRecentMentions` w PaicordLib), z serwerem i kanałem, kropką nieprzeczytanych, filtrami „tylko odpowiedzi” i „bez @everyone/@here”, „Mark All as Read” i doładowywaniem starszych. Znajomi przeniesieni do arkusza pod przyciskiem w rogu (plakietka z zaproszeniami). Plakietka na zakładce Messages liczy nieprzeczytane DM-y; wzmianki z serwerów zostają w liście, bo potrafią iść w tysiące.
   - [x] Search jako własna funkcja, zakładka przed Ustawieniami: jedno pole szuka serwerów, kanałów, osób i wiadomości. Stuknięcie w serwer, kanał lub osobę zamienia je w token filtra (zawęża następne wyniki), strzałka otwiera. Serwery, kanały i osoby lokalnie i od razu (osoby na serwerze dociągane przez gateway op 8), wiadomości przez nowe `searchGuildMessages` / `searchChannelMessages` w PaicordLib z filtrem „zawiera” (link, obraz, plik…). Wiadomości wymagają serwera, kanału albo osoby z DM. Przy okazji: wartości w zapytaniach URL są poprawnie escapowane (`&`, `=`, `+`, `#`).
   - [ ] Search: przejście do konkretnej wiadomości (dziś otwiera kanał), daty od–do, regex jako filtr po stronie aplikacji.
   - [ ] Zaproszenia do znajomych: akceptuj/odrzuć w Messages → Friends (dziś tylko lista).
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
   - [ ] Połączone konta (Spotify, GitHub, Steam itd.) w Ustawienia → Connections: `listOwnConnections` (`GET /users/@me/connections`) już jest w PaicordLib, brakuje interfejsu (lista, widoczność na profilu, odłączanie; dodawanie przez OAuth w przeglądarce).
   - [ ] Awatar, baner i „O mnie” per serwer (wymagają Nitro, payload już je obsługuje).
4. **Ustawienia:**
   - [x] Sekcja „Paicord” → „O Aicord”: wersja, build, licencja GPL-3, link do repozytorium; bez „Made with ❤️ by llsc12”, naklejki z CDN Discorda i przycisku Donate. Na dole dopisek, że to fork Paicorda od llsc12.
   - [x] Moje konto: nagłówek z awatarem, e-mail (zamaskowany, odkrywany stuknięciem), 2FA, Nitro, „Konto od”, ID użytkownika do skopiowania; ta sama sekcja kont co w Profilu i sekcja aplikacji Discorda (Scan QR na iOS zostaje). Przełączanie kont resetuje też stan okien, jak w menu „Account”.
   - [x] Skróty klawiszowe: lista istniejących skrótów w stylu klawiszy (aplikacja, czat, przeglądarka multimediów); na macOS dodatkowo ⇧↩ i esc w czacie.
   - [x] Debug: bez przycisku podglądu okna sponsora.
   - [x] Puste sekcje („Coming Soon”) zostają jako miejsca na przyszłe ustawienia.
   - [x] Content & Social: media wrażliwe oraz przemoc (pokaż, rozmyj, zablokuj; osobno DM od znajomych, DM od innych, serwery), filtry słów (wulgaryzmy, treści seksualne, obelgi), filtr spamu w DM, DM od członków serwerów i prośby o wiadomość dla nowych serwerów, kto może zaprosić do znajomych. Wszystko w ustawieniach proto (`textAndImages`, `privacy`), wartości domyślne według docs.discord.food.
   - [x] fix: Discord zastępuje całą grupę ustawień proto, którą dostaje (`privacy`, `status`, `textAndImages`…), zamiast scalać pola. `patchUserSettings` wysyłał same zmienione pola, więc kasował resztę grupy (np. zmiana „Share My Activity” czyściła custom status). Teraz zmiana idzie na pełnej lokalnej kopii, a wysyłane są całe zmienione grupy; da się też zapisać `false` i zero.
   - [x] Media wrażliwe w Aicordzie: flagi skanu Discorda w PaicordLib (`Attachment.Flag` `containsExplicitMedia`, `containsGoreContent` itd., nowe `Embed.flags`), a w wiadomości rozmycie z „Show” albo blokada z notką, zależnie od ustawień i pochodzenia wiadomości (DM od znajomego, DM od innej osoby, serwer; własne wiadomości bez filtra). Nie przetestowane na prawdziwym oznaczonym obrazku; tabele flag pochodzą ze streszczenia docs.discord.food.
   - [x] Filtr słów w Aicordzie („Word Filter in Aicord”, lokalnie, nie na koncie): listy LDNOOBW (CC BY 4.0, 25 języków w `Resources/WordLists`, podziękowanie w „O Aicord”) plus własne słowa. Całe słowa bez wielkości liter i znaków diakrytycznych, frazy, podciągi dla japońskiego, chińskiego i tajskiego. Zakres: DM od osób spoza znajomych albo wszystko. Trafiona wiadomość zwija się do „Hidden by your word filter · Show”.
   - [ ] Filtr słów: odmiana (lista ma formy podstawowe, „huja” przechodzi przy „huj”), cytaty w odpowiedziach i podglądy w Messages i Search pokazują tekst bez filtra. Filtry słów z konta Discorda (wulgaryzmy, treści seksualne, obelgi) w Aicordzie nie działają, bo nie wiadomo, jakiej listy używa Discord.
   - [ ] Foldery „Requests” i „Spam” w Messages. Wyjątki per serwer (`restrictedGuildIds`, `messageRequestRestrictedGuildIds`) w ustawieniach serwera.
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
