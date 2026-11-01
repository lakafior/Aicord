# Etap 15, Paczka B: integracja z systemem Apple

Notatki z sesji 1.11.2026 (gałąź `claude/pack-b-apple-b187c2`, od main `809b5d5`). Wszystko działa z danych, które aplikacja już ma, kiedy jest otwarta. Nic nie łączy się z Discordem w tle i nic nie trzyma tokenu poza aplikacją.

## Co powstało

- **Wspólne typy** (`AicordShared/`, kompilowane do aplikacji i do rozszerzenia widżetów, bez AicordKit):
  - `AicordLink`: link `aicord://channel/<serwer albo @me>/<kanał>[/<wiadomość>]` oraz identyfikator tekstowy `serwer:kanał[:wiadomość]`. Widżety, Spotlight, Handoff i App Intents prowadzą przez niego do jednego miejsca.
  - `AicordAppGroup`: ID App Group czytane z Info.plist (`AicordAppGroup` = `$(AICORD_APP_GROUP)`).
  - `WidgetSnapshot`: liczby i nazwy dla widżetu, bez treści wiadomości.
  - `VoiceCallAttributes` oraz `ToggleVoiceMuteIntent` i `LeaveVoiceCallIntent` (`LiveActivityIntent`, tylko iOS).
- **Aplikacja** (`Aicord/Common/System/`):
  - `SystemIntegration`: Spotlight, zapis danych widżetu, czyszczenie po wylogowaniu i otwieranie linków. `AicordAppState.openExternally` zastępuje prywatne `open` z `NotificationStore`; powiadomienia korzystają teraz z tej samej ścieżki.
  - `VoiceLiveActivityController` (iOS): obserwuje `GatewayStore.shared.voice` i startuje, aktualizuje albo kończy Live Activity.
  - `AicordIntents.swift`: `ChannelEntity`, `ServerEntity`, `OpenChannelIntent`, `WhatsNewInServerIntent` i `AicordShortcuts`.
- **Rozszerzenie** `AicordWidgets` (iOS i macOS): widżet „Unread” (mały, średni oraz na iOS akcesoria ekranu blokady) i Live Activity połączenia głosowego (tylko iOS).

## Decyzje

- **App Group:** `group.net.smigi.aicord` na iOS i `5TA8RF548P.net.smigi.aicord` na macOS (`$(DEVELOPMENT_TEAM).net.smigi.aicord`). Na Macu forma z prefiksem zespołu nie wymaga profilu, więc lokalny build z „Apple Development” podpisuje się bez zmian. Ustawienie `AICORD_APP_GROUP` siedzi na poziomie projektu, a oba pliki entitlements biorą je przez zmienną.
- **App ID:** dochodzi **jeden** (`net.smigi.aicord.Widgets`). Live Activity mieszka w tym samym rozszerzeniu, a App Intents są w aplikacji. Razem z aplikacją i rozszerzeniem Safari to **3 App ID, czyli dokładnie limit darmowego konta** w AltStore (Etap 12). Kolejne rozszerzenie już się nie zmieści.
- **AltStore:** przy podpisywaniu AltStore zmienia ID grup aplikacji. ID czytane z Info.plist może wtedy nie pasować do uprawnienia i widżet zostanie pusty („Open Aicord to see…”). Trzeba to sprawdzić na pierwszym wydaniu; w razie czego można czytać grupę z `ALTAppGroups`.
- **Spotlight** indeksuje DM-y (nazwa rozmówcy albo grupy), kanały tekstowe, ogłoszeń, forów, mediów i głosowe (nazwa i serwer, pomija kanały bez uprawnienia do oglądania, jeśli store serwera jest wczytany) oraz zapisane wiadomości (autor, miejsce i treść, bo treść już leży lokalnie w `SavedItemsStore`). Indeks to `CSSearchableIndex(name: "Aicord")`, odświeżany 5 s po READY i przy każdej zmianie zapisanych. Wyłącznik jest w Settings → Advanced → Spotlight. Wyłączenie, wylogowanie i zmiana konta kasują cały indeks, dane widżetu i listę kanałów dla Skrótów.
- **Widżet** liczy tak jak ikona aplikacji i lista serwerów: wzmianki (z wiadomościami w DM-ach) poza wyciszonymi miejscami, nieprzeczytane DM-y i serwery z nieprzeczytanymi kanałami, plus do 6 miejsc z największą liczbą wzmianek. Aplikacja zapisuje plik najwyżej raz na sekundę i woła `WidgetCenter.reloadTimelines(ofKind:)` tylko przy zmianie liczb. Przy wyjściu do tła (iOS) zapisuje jeszcze raz, żeby czas „sprzed …” był świeży. Timeline ma politykę `.never`, a widżet sam nic nie pobiera.
- **Live Activity:** przyciski to `LiveActivityIntent` w obu targetach. W rozszerzeniu ich `perform` nie robi nic, a system wykonuje je w procesie aplikacji, gdzie `VoiceCallIntentRouter` ma podpięte `toggleMute` i `leave`. `Activity` nie jest `Sendable`, więc aktualizacja i zakończenie szukają aktywności po ID poza aktorem głównym. Przy starcie aplikacji kończone są aktywności z poprzedniego uruchomienia.
- **App Intents:** oba mają `supportedModes = .foreground` (`openAppWhenRun` jest w 26 przestarzałe), więc aplikacja wychodzi na wierzch i korzysta z własnego połączenia. Nie ma pracy z tokenem w tle. „What's New in Server” czeka do 20 s na połączenie, bierze kandydatów jak Catch Up (`CatchUpSheet.candidates`, teraz statyczne), streszcza do 5 kanałów po 3 punkty przez `IntelligenceModel` i zwraca tekst jako wynik i dialog.
- **Bez fraz z parametrem** w `AppShortcutsProvider`: fraza „Open \(channel)” tworzyła w Skrótach kafelek dla każdej sugerowanej encji, czyli dziesiątki kafelków z nazwami DM-ów. Zostały „Open a channel in Aicord” i „What's new in Aicord”, a Siri dopyta o kanał albo serwer. Polskie frazy są w `Aicord/Resources/AppShortcuts.xcstrings`.
- **Lista kanałów dla Skrótów:** na żywo z `GatewayStore`, a bez połączenia z kopii w `Caches/ChannelDirectory.json` (tylko nazwy i ID), zapisywanej przy indeksowaniu.
- **Handoff:** `NSUserActivity` typu `net.smigi.aicord.channel` z `userInfo["link"]`, aktywna, kiedy jest wybrany kanał (`ChannelHandoff` w `RootView`). Odbiór i wyniki Spotlight idą przez `onContinueUserActivity` do `SystemIntegration.continue`.

## Co sprawdziłem

- Buildy `platform=macOS` i `generic/platform=iOS Simulator` (Debug, `-derivedDataPath` w scratchpadzie) przechodzą bez ostrzeżeń. Znikło też ostrzeżenie `appintentsmetadataprocessor` („no AppIntents.framework dependency”), które było na main.
- Mac: rozszerzenie jest w `Contents/PlugIns`, a aplikacja i widżet mają uprawnienie do grupy `5TA8RF548P.net.smigi.aicord`.
- Symulator iPhone 18 Pro (iOS 27), zalogowane konto. Zrzuty są w notatkach grupy: `side-session-notes/…/pack-b-shots/`.
  - Spotlight: log „3661 channels indexed” i „1 saved messages indexed”. Wyszukanie „jaki-batch” pokazuje kanał z serwerem, a stuknięcie otwiera kanał. Wyszukanie autora zapisanej wiadomości daje Top Hit z miejscem i treścią, a stuknięcie z innego kanału (NAScin #ogólny) otwiera #jaki-batch z podświetloną wiadomością.
  - Link `aicord://channel/<NAScin>/<#ogólny>` przez `simctl openurl` otwiera kanał.
  - Widżet: jest w galerii („Unread”), średni na ekranie głównym pokazuje prawdziwe liczby (1536 wzmianek, 70 serwerów) i 4 miejsca z wzmiankami. Po wyjściu z aplikacji czas „sprzed …” się odświeża.
  - Live Activity: dołączenie do pustego kanału głosowego „Ogólne” na NAScin pokazuje w Dynamic Island ikonę i licznik czasu, a po rozwinięciu „#Ogólne”, „Only you”, mikrofon i rozłączenie. Stuknięcie mikrofonu wycisza (ikona robi się czerwona) i drugi raz odcisza. Rozłączenie z wyspy kończy połączenie i Live Activity znika.
  - Skróty: w Library → Aicord są dwa kafelki „Open Channel” i „What's New”. Uruchomienie „Open Channel” pokazuje wybór kanału z listą z aplikacji, więc zapytanie encji działa.
- **Błąd znaleziony i poprawiony w trakcie:** zapisana wiadomość z typem `UTType.message` nie pojawiała się w Spotlight na iOS 27. Z `UTType.text` jest widoczna.

## Czego nie sprawdziłem

- **Uruchomienia „Open Channel” do końca:** wybór przy uruchomieniu nie ma wyszukiwarki i zaczyna się od DM-ów, a w DM-y nie wolno było wchodzić. Wyszukiwarka akcji w edytorze skrótu w symulatorze była pusta. Sam `perform` korzysta z tej samej ścieżki co link widżetu, który działa.
- **„What's New in Server”:** nie uruchomiłem go, bo aplikacja Skróty w symulatorze się zamknęła. Siri też nie było jak sprawdzić.
- **Handoff:** wymaga dwóch urządzeń z tym samym kontem Apple i podpisu tym samym zespołem. W symulatorze się nie da.
- **Widżet na macOS i Live Activity na ekranie blokady** (sprawdzony tylko Dynamic Island), widżety akcesoriów na ekranie blokady oraz stuknięcie w wiersz widżetu. Nie stukałem, bo otwarcie kanału z wzmiankami oznacza go jako przeczytany na koncie, a sam link jest sprawdzony przez `openurl`.
- **Czyszczenie przy wylogowaniu:** sprawdzone tylko w kodzie, nie wylogowywałem konta.
- **AltStore i App Group** na prawdziwym urządzeniu (patrz Decyzje).

## Uwagi

- W symulatorze dalej działa testowa reguła alertu „the” z Paczki A (powiadomienia „Keyword: the”), choć notatki A mówią, że została usunięta. Nie ruszałem jej.
- W Skrótach w symulatorze został pusty „New Shortcut” z próby edytora.
- Wyciszenie z Live Activity zmienia zapisane ustawienie wyciszenia, tak jak przycisk w aplikacji. Po teście zostało odciszone.
