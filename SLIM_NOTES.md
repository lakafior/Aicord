# Odchudzenie biblioteki i zmiana nazw (Etap 7 i 5.4)

Notatki z autonomicznej sesji na gałęzi `claude/slim-lib-b07334` (od `main` na `5c0818d`).
Nic nie jest scalone ani wypchnięte. `README.md`, `ROADMAP.md` i `SHIPPED.md` są nietknięte.

## Commity

| Commit | Co |
|---|---|
| `d099620` | Usunięcie endpointów i modeli tylko dla botów |
| `69cc36e` | Usunięcie shardowania i uwierzytelniania bota |
| `c6d0940` | `@Indirect`: duże zagnieżdżone pola poza strukturą (kod kopiowania) |
| `6a32dc6` | `PaicordLib` → `AicordKit`, scalenie małych modułów, sprzątanie po DiscordBM |
| `caa0b5d` | `Textual`: bez stylu GitHub, przestarzałego API i tabel |
| `55bd284` | Target, schematy, produkt i folder `Paicord` → `Aicord` |

Po każdym commicie przechodziły: build Debug iOS (symulator `10C26E42-…`), build Debug macOS
i `swift test` w pakiecie biblioteki.

## Rozmiar binarki (Release, iOS arm64, `generic/platform=iOS`)

Mierzone z mapy linkera (`LD_GENERATE_MAP_FILE=YES`). „Kod aplikacji” to obiekty targetu aplikacji.

| Etap | Binarka | `__TEXT` | `__text` | Kod aplikacji | `DiscordModels` | `Textual` | `DiscordHTTP` |
|---|---|---|---|---|---|---|---|
| Przed (`main`) | 51,88 MB | 22,59 MB | 20,04 MB | 11,81 MB | 7,48 MB | 1,14 MB | 0,48 MB |
| Po usunięciu kodu botów (1–2) | 49,93 MB | 21,77 MB | 19,30 MB | 11,81 MB | 6,63 MB | 1,14 MB | 0,42 MB |
| `@Indirect` na wiadomościach | 44,03 MB | 15,84 MB | 13,37 MB | 6,97 MB | 5,54 MB | 1,14 MB | 0,42 MB |
| `@Indirect` na użytkownikach, profilach, zaproszeniach, emoji | 42,30 MB | 14,11 MB | 11,63 MB | 6,34 MB | 4,44 MB | 1,14 MB | 0,42 MB |
| **Po wszystkim** | **41,86 MB** | **14,01 MB** | **11,56 MB** | **6,34 MB** | **4,45 MB** | **1,04 MB** | **0,42 MB** |

Łącznie: binarka −10,0 MB (−19%), `__text` −8,5 MB (−42%).

Witnessy kopiowania w `DiscordModels` (`assignWithCopy`, `assignWithTake`, `initializeWithCopy`,
`destroy`): **2,71 MB → 0,53 MB**.

## Decyzje

### 1. Kod tylko dla botów

Przed usunięciem sprawdziłem użycia w aplikacji (skrypt przeszukujący `Paicord/`, bibliotekę i testy).
Aplikacja używała 17 ze 170 metod `DiscordClient+APIEndpoint`, żadna z usuniętych kategorii.

- **Usunięte endpointy** (`APIEndpoint`, `DiscordClient+APIEndpoint`): komendy aplikacji (15),
  interakcje (8), logi audytu, automoderacja (5), webhooki (13), entitlementy (4), SKU,
  metadane połączeń ról aplikacji (4), `getBotGateway`, `getOwnOauth2Application`,
  `get/updateOwnApplication`, oraz 4 endpointy członków, które biblioteka blokowała dla
  tokenu użytkownika (`assertBotOnly`): `listGuildMembers`, `searchGuildMembers`,
  `addGuildMember`, `listActiveGuildThreads`. Wykomentowane bloki kodu z DiscordBM też zniknęły.
- **Zachowane dla użytkownika**: `getThreadMember` i `listThreadMembers` (warianty
  `…WithMember` działają z tokenem użytkownika), szablony serwerów, wydarzenia, naklejki itd.
  Zakres trzymał się listy z zadania; ogólne endpointy serwerów zostają na przyszłe funkcje.
- **Modele**: usunięte pliki `Application Commands`, `Audit Log`, `Auto Moderation`,
  `GatewayEventHandler` (protokół obsługi zdarzeń dla botów, nieużywany).
  `Interaction` stał się przestrzenią nazw (`enum`) z tym, czego potrzebuje wyświetlanie:
  `Kind`, `ContextKind`, `ResolvedData` (przeniesione z `Interaction.ApplicationCommand.ResolvedData`
  do `Interaction.ResolvedData`), `MessageInteraction` i **wszystkie komponenty wiadomości**
  (`ComponentSwitch`, `ActionRow`, przyciski, menu): `MessageBody` renderuje komponenty v2,
  a `Message.components` je dekoduje. Zniknęły pomocniki `require…` dla botów.
- **Webhooki**: model `Webhook` i `WebhookSnowflake` zostają (wiadomości od webhooków mają
  `webhook_id`). Usunięte: `WebhookAddress` i payloady wykonywania/tworzenia webhooków.
- **`Entitlement` i `SKU`** zostają: subskrypcja Nitro użytkownika (`Subscription`) używa ich identyfikatorów.
- **Zdarzenia Gateway** dla botów, interakcji i komend (`ENTITLEMENT_*`, `GUILD_AUDIT_LOG_ENTRY_CREATE`,
  `AUTO_MODERATION_*`, `INTERACTION_*`, `APPLICATION_COMMAND_*`, `GUILD_APPLICATION_COMMAND_INDEX_UPDATE`,
  `WEBHOOKS_UPDATE`) są przyjmowane z `data == nil` zamiast rzucać `unhandledDispatchEvent`,
  więc nie pojawiają się nowe błędy dekodowania. Aplikacja żadnego z nich nie obsługiwała.
- **Wysyłanie interakcji jako użytkownik** (`Payloads.CreateInteraction`, `Interaction.Data`)
  też usunięte: nie było endpointu ani wywołań. Gdyby kiedyś trzeba było klikać przyciski botów
  albo używać komend z ukośnikiem, kod jest w historii przed `d099620`.
- `StringIntDoubleBool` (tylko dla opcji komend) i `DiscordUtils.slashCommand` usunięte.

### 2. Shardowanie i uwierzytelnianie bota

`ShardCoordinator`, `Gateway.Intent` i `correspondingIntents`, inicjalizatory `Identify` dla
botów, pola `intents` i `shard`, `BotConnectionInfo`, moduł `DiscordAuth` (`BotAuthManager`),
`AuthenticationHeader.botToken`/`.oAuthToken`, `appId`/`requireAppId`, `assertBotOnly`/`assertUserOnly`
i błędy z nimi związane, przestarzałe `makeEventsStream`/`makeEventsParseFailureStream`.
Pola `intents`/`shard` były dla użytkownika zawsze `nil` i nie trafiały do JSON-a, więc
wysyłany `IDENTIFY` się nie zmienia.

### 3. Kod kopiowania

Pomiar pokazał, że problemem nie były `Guild` ani `Gateway.Ready` (ich witnessy miały 2–8 KB),
tylko struktury wiadomości: `DiscordChannel.Message`, `PartialMessage`, `Gateway.MessageCreate`
i typy, które je zawierają (`SavedMessage`, `SupplementalMessageRequest`,
`Responses.ChannelWithMessage`), po ~160–250 KB każda. Do tego kod aplikacji inline'ował
kopiowanie tych struktur w widokach (11,8 MB kodu aplikacji).

Rozwiązanie: wrapper `@Indirect` (w `Shared.swift`), który trzyma wartość w klasie
z copy-on-write. Kopia struktury to jeden retain na pole zamiast kopiowania pole po polu.
Semantyka wartości zostaje (test `testIndirectFieldsKeepOptionalCodingAndValueSemantics`
sprawdza niezależność kopii, `==`, brakujące i `null` klucze oraz pomijanie `nil` przy kodowaniu).
Przeciążenia `KeyedDecodingContainer.decode`/`KeyedEncodingContainer.encode` dla `Indirect<T?>`
zachowują zachowanie syntetyzowanego `Codable` dla opcjonali.

Pola z `@Indirect`:
- wiadomości (`Message`, `PartialMessage`, `MessageCreate`): `author`, `activity`, `application`,
  `message_reference`, `interaction_metadata`, `interaction`, `thread`, `components`,
  `role_subscription_data`, `resolved`, `poll`, `call`, `member`;
- `DiscordUser`, `PartialUser`, `MentionUser`: `collectibles`, `avatar_decoration_data`, `primary_guild`;
- `DiscordUser.Profile`: `application`, `user_profile`, `guild_member`, `guild_member_profile`;
- `Invite`, `InviteWithMetadata`, `PartialInvite`, `Gateway.InviteCreate`: `guild`, `channel`,
  `inviter`, `target_user`, `target_application`, `guild_scheduled_event`;
- `Emoji`: `user`.

Dalej nie szedłem: kolejne typy dawały po kilkadziesiąt KB.

### 4–5. Moduły i nazwa

- Pakiet `PaicordLib/` → **`AicordKit/`**, produkt i moduł parasolowy `AicordKit`
  (aplikacja robi `import AicordKit`), testy `DiscordBMTests` → `AicordKitTests`.
- `DiscordCore` (konfiguracja globalna, rozszerzenia) i `DiscordUtilities` (`DiscordUtils`)
  weszły do `DiscordModels`; `DiscordAuth` zniknął w kroku 2. Zostały moduły
  `DiscordModels`, `DiscordHTTP`, `DiscordGateway`, `DiscordVoice` (+ `COpusShim`, makro
  `UnstableEnumMacro`). Nazw `Discord*` nie zmieniałem: opisują protokół, a osobne moduły dają
  szybszą kompilację przyrostową; `DiscordVoice` musi zostać osobno przez interop C++ (DaveKit).
- Usunięte: wykonywalny `TestCode` (ręczny test logowania QR), wtyczka `GenerateAPIEndpoints`
  (nie była nawet zadeklarowana w `Package.swift`; `APIEndpoint.swift` edytuje się teraz ręcznie).
- Sprzątanie po DiscordBM: linki do zgłoszeń w DiscordBM i w llsc12/Paicord z komentarzy
  błędów, domyślne `browser/device = "DiscordBM"` (nieużywany inicjalizator),
  User-Agent „DiscordBM (…)”, flaga `DISCORDBM_ENABLE_LOGGING_DURING_DECODE` →
  `AICORDKIT_ENABLE_LOGGING_DURING_DECODE`, nagłówki plików `//  PaicordLib` → `//  AicordKit`.
- `AicordKit/LICENSE`: „AicordKit (formerly PaicordLib) is a fork of DiscordBM”; licencja
  Apache 2.0 DiscordBM i uznanie autorstwa zostają.

### 6. `Textual`

- Usunięte: zestaw stylów GitHub (`StructuredText/Style/GitHub`, `InlineStyle+GitHub`),
  `Deprecations.swift` (API sprzed 0.2.1) oraz **renderowanie tabel** (widoki `Table`/`TableCell`,
  `TableLayout`, style tabel, modyfikatory `tableStyle`/`tableCellStyle`/`tableBackground`/
  `tableOverlay`/`tableCellSpacing`). `DiscordMarkdownPreprocessor` escapuje składnię tabel,
  więc tabela nigdy nie trafiała do widoku. Kopiowanie tekstu (`Formatter`) nadal obsługuje tabele.
- Zostało: `InlineText` (część wewnętrzna `StructuredText`), podświetlanie kodu, styl domyślny
  (Discord korzysta z jego akapitów i list).

### 7. Etap 5.4: `Paicord` → `Aicord`

- `Paicord.xcodeproj` → `Aicord.xcodeproj`, `Paicord.xcworkspace` → `Aicord.xcworkspace`,
  schematy `Aicord` i `Aicord Release`, target i produkt `Aicord` (`Aicord.app`,
  `CFBundleName`/`CFBundleExecutable` = Aicord, więc menu i Dock na macOS pokazują „Aicord”).
- Folder źródeł `Paicord/` → `Aicord/` (z `Aicord.entitlements`), typy `PaicordApp`,
  `PaicordAppState`, `PaicordSheetsAlerts`, `PaicordCommands`, `PaicordImagePipeline`,
  `PaicordChatLink`, `PaicordCodeBlockStyle` → `Aicord…`, folder `PaicordLib++` → `AicordKit++`,
  nagłówki plików, subsystem loggera → `net.smigi.aicord`.
- `.github/workflows/build_pr.yml` i `.github/CONTRIBUTING.md` wskazują nowe nazwy.
- Usunięty śledzony plik `UserInterfaceState.xcuserstate` (stan Xcode llsc12).
- **Bez zmian** (dane): `PRODUCT_BUNDLE_IDENTIFIER = net.smigi.aicord`, usługa pęku kluczy
  `net.smigi.aicord.Accounts`, katalog cache `net.smigi.aicord.imagecache`, klucze
  `UserDefaults` `Paicord.*`, wewnętrzne linki `paicord://` i atrybuty `paicord…Mention`.
  Uznanie autorstwa llsc12 w About (`upstreamURL`), licencji i komentarzach „Ported from…” zostaje.

## Testy

111 → **105**. Usunięte testy funkcji botów (7):
- `DiscordModelsTests.testWebhookAddress`, `testInteractionDataUtilities`,
  `testApplicationCommandUtilities`, `testStringIntDoubleBoolUtilities`;
- `BotAuthManagerTests` (2 testy);
- `ClientConfigurationTests.testAuthenticationHeader` (wyciąganie `appId` z tokenu bota).

Dodany 1: `testIndirectFieldsKeepOptionalCodingAndValueSemantics`.
Zmienione bez utraty pokrycia: `testEventDecode` (zdarzenie logu audytu jest teraz przyjmowane
z `data == nil`), `HTTPRateLimiterTests` (endpoint spoza globalnego limitu to teraz
`getExperiments` zamiast odpowiedzi na interakcję), `ClientConfigurationTests` (inny endpoint
w teście cache), `DiscordUtilsTests` (bez `slashCommand`).

## Sprawdzenie w symulatorze

iPhone 18 Pro (`10C26E42-…`), build Debug z tej gałęzi zainstalowany na miejsce poprzedniego:
- zalogował się sam, bez ponownego logowania (ten sam identyfikator i pęk kluczy);
- wczytał listę serwerów i kanały;
- otworzył kanał `#rules` (wybrany, bo nie miał nieprzeczytanych): markdown, listy, pogrubienia,
  własne emoji i reakcje wyglądają jak wcześniej;
- przyszło powiadomienie w aplikacji o nowej wiadomości (zdarzenia Gateway działają);
- Settings i podstrona Connections się otwierają i wczytują.

Niczego nie wysłałem ani nie zmieniłem na koncie. Aplikacji na macOS nie uruchamiałem
(tylko build); nazwę w menu potwierdza `CFBundleName = Aicord` w zbudowanym `Info.plist`.

## Proponowane wpisy

### ROADMAP: do odhaczenia

- Etap 5.4: „Zmiana nazw targetów/schematów (`Paicord` → `Aicord`) oraz odniesień do oryginalnego repozytorium.”
- Etap 7.1: wszystkie trzy punkty (kod botów, shardowanie, kod kopiowania). Przy trzecim
  warto poprawić opis: winne były struktury wiadomości, nie `Guild`/`Gateway.Ready`.
- Etap 7.2: oba punkty (scalenie modułów, nazwa `AicordKit` i sprzątanie po DiscordBM).
- Etap 7.3: usunięcie nieużywanych elementów `Textual`.
- W ROADMAP i README trzeba zaktualizować ścieżki: `PaicordLib/` → `AicordKit/`,
  `Paicord/` → `Aicord/` (np. `Aicord/Resources/AppIcon.icon`), `Paicord.xcodeproj` → `Aicord.xcodeproj`,
  sekcja Building: `Aicord.xcworkspace` i schemat `Aicord`.

### ROADMAP: nowe propozycje

- `Textual/Tests` nie ma targetu testów w `Package.swift` (testy snapshotowe nigdy się nie
  uruchamiają). Albo dodać target z zależnością od swift-snapshot-testing, albo usunąć katalog.
- Dalsze odchudzanie `DiscordModels` (4,45 MB): największe są teraz `CodingKeys` (~0,9 MB)
  i `init(from:)`/`encode(to:)`; `SwiftProtobuf` to 1,15 MB.

### README „New & fixed”

> **Lighter app.** The Discord library is now Aicord's own `AicordKit`: bot-only endpoints,
> sharding and bot authentication are gone, and large message and user models are stored more
> compactly. The iOS app binary shrank from 51.9 MB to 41.9 MB, and the compiled code by 42%.
> The Mac app now shows “Aicord” in the menu bar and Dock.

## Ryzyka i rzeczy do sprawdzenia przy przeglądzie

- **`@Indirect`** dodaje alokację na każde niepuste opakowane pole przy dekodowaniu
  (kosztem mniejszego kopiowania). W symulatorze nie widać spowolnienia, ale nie profilowałem.
  Odczyt to jedno wyłuskanie wskaźnika; porównanie zaczyna od porównania referencji.
- Zdarzenia Gateway botów/interakcji mają teraz `data == nil`. Aplikacja ich nie obsługiwała.
- User-Agent dla klienta bez uwierzytelnienia i bez callbacku captcha (`.none`) to teraz
  UA klienta zamiast „DiscordBM (…)”. Aplikacja zawsze podaje callback, więc nie tworzy takiego klienta.
- Renderowanie tabel w `Textual` zniknęło. Gdyby preprocesor przestał je escapować, tabela
  pokaże się jako akapit.
- **Konflikty przy scalaniu**: przeniesione są katalogi `Paicord/` → `Aicord/`,
  `PaicordLib/` → `AicordKit/` i projekt Xcode. Git wykrywa zmiany nazw, ale gałęzie
  zaczęte przed tą zmianą będą wymagały rebase'u; zmiany w `project.pbxproj` z innych gałęzi
  trzeba nanieść ręcznie, jeśli dodają pliki.
- `Package.resolved` jest w `.gitignore`, więc wersje zależności rozwiązuje każdy build od nowa
  (bez zmian w tej gałęzi, tylko uwaga).
