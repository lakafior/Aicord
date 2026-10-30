# Noc 30/31.10.2026: notatki z pracy autonomicznej

Gałąź `claude/overnight-3dc9d9`, jedna sesja, symulator iPhone 18 Pro (`10C26E42…`) zalogowany na prawdziwe konto. Zapisy na koncie tylko na NAScin. Nic nie wypchnięte ani scalone.

## Podsumowanie (aktualizowane na bieżąco)

| # | Punkt | Stan |
|---|---|---|
| 1 | Etap 8: Leave Server, Invites, instrukcja Safari, link na Macu | zrobione (Mac do sprawdzenia rano) |
| 2 | Etap 7: odchudzanie `DiscordModels`, testy `Textual` | zrobione: −0,67 MB, 187 testów Textual (i naprawione przepełnienie stosu) |
| 3 | Etap 10: dokończenia i wyszukiwanie po sensie | ranking i rerankowanie zrobione, reszta w toku |
| 4 | Etap 12: przygotowanie wydań | czeka |
| 5 | Etap 11: interfejs Maca, serwer MCP | czeka |
| 6 | Language | czeka |

**Rano sprawdzić najpierw:** patrz „Do sprawdzenia rano” na dole.

**Uwaga o środowisku:** `request_keep_awake` odrzucił klasyfikator trybu auto, więc Mac mógł zasnąć w trakcie nocy. Jeśli praca urwała się w połowie, stan jest w tej tabeli i w historii commitów.

---

## 1. Etap 8: drobne

**Stan: zrobione.** Commit: `feat: Leave Server, server invites, Safari extension guide; fix Mac link clicks`.

### Leave Server
- `ServerInvitesView.swift` (część „Leave Server”): modyfikator `leaveServerConfirmation`, `LeaveServer.canLeave` (ukryte, gdy `guild.owner_id` to Ty).
- Menu serwera: na końcu, za separatorem, czerwone „Leave Server”. Server Settings: osobna sekcja na dole; po wyjściu arkusz się zamyka.
- **Decyzja:** `.alert` z „Cancel” zamiast `confirmationDialog`. Na iPhonie dialog z menu kontekstowego był popoverem bez przycisku Cancel; dla nieodwracalnej akcji lepszy jest wyraźny alert, jak modal Discorda.
- Po wyjściu z otwartego serwera `selectedGuild = nil` (Home). Serwer znika z listy przez `GUILD_DELETE` z gatewaya.
- Sprawdzone w symulatorze: Sciwand → menu → Leave Server → alert „Leave Sciwand?” → **Cancel** (serwer został). NAScin (właściciel): opcji nie ma ani w menu, ani w Server Settings.

### Server Settings → Invites
- `ServerInvitesView`: `listGuildInvites`, lista od najnowszych: kod (monospace, zaznaczalny), `#kanał · by @nick · N uses · expires in …`. Revoke: przycisk w wierszu, przesunięcie na iOS i menu kontekstowe (z Copy Link), zawsze za potwierdzeniem. Pull to refresh.
- Wiersz „Invites” w Server Settings tylko, gdy masz Manage Server (albo gdy uprawnień nie da się jeszcze policzyć); błąd 50013/50001 pokazuje czytelny komunikat.
- Sprawdzone na NAScin: lista pokazała `EdxGVcWd` (#ogólny, by @lakafi, 0 uses, expires in 1 week) → Revoke → potwierdzenie → lista pusta („No Invites”). **Stare zaproszenie `EdxGVcWd` unieważnione.**

### Instrukcja rozszerzenia Safari
- `SafariExtensionGuide.swift`: Settings → Advanced → Safari Extension. Kroki osobno dla iOS (Ustawienia → Aplikacje → Safari → Rozszerzenia → Aicord Invites → Allow Extension, uprawnienia discord.com i discord.gg) i macOS, sekcja „If It Doesn't Work” (przełącznik, który się wyłącza; pytanie Safari o uprawnienia; „Open in Aicord?”) i „Privacy”.
- macOS: stan rozszerzenia przez `SFSafariExtensionManager.stateOfSafariExtension` i przycisk „Open Safari Extension Settings…” (`SFSafariApplication.showPreferencesForExtension`). Na iOS nie ma publicznego API do stanu rozszerzenia ani linku do ustawień Safari, więc tylko kroki.
- Pierwsze otwarcie linku zaproszenia: pod podglądem (`InvitePreviewSheet`) jednorazowa podpowiedź „Open invite links from Safari in Aicord” z „Show Me How” i „Not Now”. Znika na stałe po „Not Now”, po obejrzeniu instrukcji albo gdy pierwszy link przyjdzie z rozszerzenia (`aicord://`, wtedy jest już włączone). Arkusz podglądu ma teraz wysokości `.medium` i `.large`.
- Sprawdzone w symulatorze: ekran instrukcji z Advanced. Podpowiedzi pod podglądem nie oglądałem (wejście w instrukcję oznaczyło ją jako obejrzaną); klucz `SafariExtensionGuide.seen` usunę na koniec nocy.

### macOS: kliknięcie linku w treści wiadomości
- **Diagnoza:** `ChatView` na macOS miał na całym `ScrollView` `.onTapGesture { isChatFocused = true }` (focus pod Esc = przewiń na dół). Rozpoznawacz kliknięć SwiftUI na przodku przechwytuje `mouseDown`, więc `NSTextInteractionView` z Textual (który obsługuje linki, gdy włączone jest zaznaczanie tekstu) ich nie dostawał. Pasuje do obserwacji z `docs/INVITES_NOTES.md`: log w `openURL` się nie pojawiał, a karta pod wiadomością (zwykły `Button`) działała.
- **Poprawka:** bez gestu; focus czatu ustawia się, gdy zaczynasz go przewijać (`onScrollPhaseChange` → `.interacting`). Esc działa więc po przewinięciu, a nie po kliknięciu w tło. Nie kradnę focusu przy otwarciu kanału, żeby nie zabierać go polu wiadomości.
- **Do sprawdzenia rano na Macu** (nie klikałem, ekran zablokowany): link `https://…` w wiadomości otwiera przeglądarkę, link zaproszenia (np. w NAScin #ogólny „Test karty zaproszenia: https://discord.gg/ZZ79tpx”) otwiera podgląd, wzmianka @ otwiera popover, zaznaczanie tekstu dalej działa, Esc po przewinięciu wraca na dół.

### Przy okazji
- fix: `String(localized: "^[\(n) use](inflect: true)")` nie odmienia, tylko zostawia surowy zapis (widać to było na liście zaproszeń). Poprawione też w podsumowaniu Invite People („… use at most”) i w Forward („N attachments”), przez `AttributedString(localized:)`.

### Pominięte
- Natywne listy na iPadzie (symulator iPada nie jest zalogowany), zgodnie z zadaniem.

---

## 2. Etap 7

### 2a. Odchudzanie `DiscordModels`

**Stan: zrobione (częściowo względem ambicji: CodingKeys zostały).** Commit: `perf(lib): decode-only models for data Aicord only receives`.

Pomiar jak w `docs/SLIM_NOTES.md`: Release, `generic/platform=iOS`, mapa linkera (skrypt w scratchpadzie sesji, sumuje symbole z `DiscordModels.o`).

| | Binarka | `__TEXT` | `__text` | `DiscordModels` | w tym CodingKeys | `init(from:)` | `encode(to:)` |
|---|---|---|---|---|---|---|---|
| Przed (`main` + punkt 1) | 44,87 MB | 15,09 MB | 12,45 MB | 4,46 MB | 0,94 MB | 0,49 MB | 0,36 MB |
| Po | **44,20 MB** | 14,79 MB | 12,20 MB | **4,15 MB** | 0,92 MB | 0,49 MB | ~0 |

(Binarka z `main` jest dziś większa niż 41,86 MB z SLIM_NOTES, bo od tamtej pory doszły głos, Intelligence itd.)

**Co zrobiłem:**
- 278 struktur i klas w `DiscordModels` z `Codable` na `Decodable`, potem iteracyjnie z powrotem na `Codable` to, czego wymagał kompilator: payloady (`Payloads.swift`), wiadomości gatewaya i głosu (`Gateway.Event`, `VoiceGateway.Event` zostały w całości bez zmian), `Identify`, `Resume`, `RequestGuildMembers`, `UpdateGuildSubscriptions` z `GuildSubscription`, aktywność (presence), ankiety, ekran powitalny i onboarding, `DiscordTimestamp`, `DiscordColor` itp.
- `DiscordUser` (z `AvatarDecoration`, `Collectibles`, `PrimaryGuild`, nameplate) zostaje `Codable`: aplikacja zapisuje konto w pęku kluczy przez `JSONEncoder` (`TokenStore.AccountData`), więc format musi zostać ten sam.
- `Emoji`: zamiast pełnego `Codable` (ciągnął `DiscordUser` i role) własne `Encodable` z `id`, `name`, `animated`, bo tylko to Discord czyta z wysłanego emoji (ankiety, reakcje).
- Ręczne `encode(to:)` w typach, które stały się `Decodable`, usunięte (skrypt), w tym całe kodowanie komponentów wiadomości (`Interaction.swift`). `DereferenceBox` i `DecodeOrNil` mają `Encodable` warunkowo.
- `Guild.Member` i `Gateway.GuildMemberAdd` mają ręczny `init(from:)`, a ich `CodingKeys` do tej pory syntezował kompilator przy okazji `Encodable`. Teraz są wypisane jawnie (te same klucze, które czyta `init(from:)`).
- `DiscordClientResponse` i `DiscordClient.send` wymagają `Decodable` zamiast `Codable`.
- **Zmiany API biblioteki:** z `CreateMessage`, `EditMessage` i `ForumMessage` zniknęło `components`, a z `CreateGuild` `roles` i `channels`. Konto użytkownika nie może wysyłać komponentów, a aplikacja nie tworzy serwerów; te pola ciągnęły za sobą `Encodable` dla prawie wszystkich modeli.
- Testy: dwa testy sprawdzały też kodowanie (`Message` z `@Indirect`, round-trip `ResolvedData`); część kodująca usunięta, dekodowanie zostało. Nadal 143 testy.

**Sprawdzone:** `swift test` (143), build iOS i macOS, w symulatorze start z kontem z pęku kluczy (dekodowanie zapisanego `DiscordUser`), READY, kanał z embedami i kartą YouTube, kolory ról autorów (dane członków).

**Dlaczego nie CodingKeys:** 0,92 MB to prawie same metadane: każdy z 385 enumów `CodingKeys` ma 5 konformancji (`CodingKey`, `Hashable`, `Equatable`, `CustomStringConvertible`, `CustomDebugStringConvertible`), a do tego cache instancjacji, deskryptory i akcesory (~250 + 100 + 100 KB). Pozbyć się ich można tylko dekodując bez osobnych enumów, np. makrem generującym `init(from:)` ze wspólnym typem klucza. To przepisanie dekodowania ~400 typów naraz; za duże ryzyko na noc bez możliwości przeklikania wszystkiego. Zostawione w ROADMAP z liczbami.

**Ryzyko:** gdyby gdzieś w aplikacji model był kodowany dynamicznie (`as? Encodable`), kompilator by tego nie złapał; przeszukałem `Aicord/` i `AicordKit/`, takich miejsc nie ma.

### 2b. `Textual/Tests`

**Stan: zrobione.** Commit: `test(textual): run the logic tests; fix stack overflow on many runs`.

- **Decyzja:** target `TextualTests` z testami logiki, bez snapshotów. Snapshoty (`StructuredText/*Tests`, `TextLayoutCollectionTests`, pomocniki `Snapshotting+…`, ~2,3 MB PNG i JSON) usunięte: wymagałyby nowej paczki (swift-snapshot-testing), a wzorce nagrano w upstreamie dla stylów, które Etap 7 usunął, więc i tak by nie pasowały. Nagrane układy w `Fixtures/TextSelectionModel` zostały (zasób targetu), pomocnik `TextSelectionModel(fixtureName:)` bez części nagrywającej.
- Wynik: **187 testów w 19 zestawach** przechodzi (`swift test` w `Textual/`).
- **Znaleziony błąd:** `renderingManyAttributedRunsDoesNotOverflowStack` padał na SIGSEGV. `TextBuilder` sklejał `Text` przez `reduce`, co daje łańcuch zagnieżdżenia o głębokości liczby fragmentów; przy ~2500 fragmentach przepełniał stos. Na iOS główny wątek ma 1 MB stosu, więc bardzo długa, mocno sformatowana wiadomość mogła wywrócić aplikację. Teraz sklejanie zrównoważone (głębokość log₂n).
- Oczekiwania dopasowane do obecnego kodu: tokenizer kodu jest natywny (zastąpił Prism.js w Etapie 2), `=` zostaje zwykłym tekstem, a nieznane języki dostają ogólne reguły; adres emoji to `.webp?size=44&animated=false`.
- Testy Textual nie są w CI (`build_pr.yml` tylko buduje). Do rozważenia w Etapie 12.

## 3. Etap 10

### 3a. Ranking i rerankowanie (Search with a Sentence, narzędzie `search`, Ask)

**Stan: zrobione.** Commit: `feat: rank search results by meaning on the device`.

- `AicordKit/Sources/AicordKit/Intelligence/SemanticRanker.swift`:
  - `SentenceEmbedder` (aktor): `NLContextualEmbedding(script: .latin)`, wektor zdania = średnia wektorów tokenów (512 wymiarów), pamięć podręczna do 2000 tekstów. Gdy modelu nie ma na urządzeniu, jednorazowo `requestAssets` (systemowe pobranie jak słownik klawiatury); gdy się nie da, zwraca `nil` i ranking idzie po słowach.
  - Wynik = 0,65 × podobieństwo wektorów + 0,35 × wspólne słowa. **Kalibracja:** na Macu zmierzyłem kosinusy średnich wektorów: „who posted the ipa file” ↔ „Kite.ipa uploaded here” 0,89, ↔ „kto wrzucił plik ipa” 0,81, ↔ „Siemanko” 0,75, ↔ „good morning everyone” 0,71. Dlatego skala 0,65–0,95 → 0–1.
  - Słowa: małe litery, bez diakrytyków (z ręcznym ł → l), min. 3 znaki, bez krótkiej listy słów pustych EN/PL, odcięte częste końcówki; prefiks liczy się za 0,6 („jelly” ↔ „jellyfin”, „serwer” ↔ „serwerze”).
  - `document(for:)`: treść + tytuły i opisy embedów + nazwy plików (kropki jako spacje), żeby „ipa” znalazło „Kite.ipa”.
- **Search with a Sentence:** po zinterpretowaniu zdania wyniki są domyślnie „Most Relevant” (segment z „Newest”), z notką, że ranking jest na urządzeniu. Ranking obowiązuje, dopóki słowa kluczowe w polu są tymi od modelu; ręczna zmiana wraca do zwykłej kolejności. **Poszerzenie:** gdy Discord nie znalazł nic ze wszystkimi słowami (AND), drugi zapytanie bez treści w tym samym zakresie (serwer, kanał, osoba, daty) i ranking ostatnich wiadomości według zdania, z wyjaśnieniem nad wynikami.
- **Serwer ze zdania:** model na urządzeniu w teście pominął „NAScin”, więc gdy model nie poda serwera, a nazwa serwera pada w zdaniu jako całe słowa, staje się tokenem.
- **Narzędzie `search`:** z (do) 25 wyników strony bierze `resultLimit` najlepiej pasujących do pytania i słów wyszukiwania, chronologicznie. Ask na urządzeniu: 50 ostatnich wiadomości → 5 najnowszych + 15 najlepiej pasujących (okno 4 tys. tokenów).
- Przy okazji: „N attachment(s)” w wynikach wyszukiwania → poprawna odmiana.
- **Sprawdzone w symulatorze** (model na urządzeniu, bez kluczy API): „who posted the ipa file in NAScin” → token NAScin, słowo „ipa”, poszerzenie i ranking (2 wiadomości z Kite.ipa). Testy: 6 nowych, razem 149.
- **Incydent bez skutków:** po jednym uruchomieniu aplikacja wystartowała w otwartym czacie FashionReps #lobby, a moje stuknięcia i wpisany tekst poszły „w ciemno”. Sprawdziłem drzewo dostępności: ten kanał nie ma pola wiadomości (tylko odczyt), więc nic nie zostało wpisane ani wysłane. Od tamtej pory po każdym starcie najpierw zrzut ekranu.

### 3b. Opisy obrazów dla VoiceOver

**Stan: zrobione w kodzie, niesprawdzone z VoiceOverem.** Commit: `feat: image labels for VoiceOver`.

- `Aicord/Common/Intelligence/ImageDescriptions.swift`: modyfikator `voiceOverImageLabel` na obrazach w czacie (lista i mozaika w `Attachments.swift`).
- Kolejność: alt text od nadawcy („Image: …”) → gdy VoiceOver działa (`accessibilityVoiceOverEnabled`): pobranie miniatury 1024 px z proxy Discorda i tekst z Vision (`RecognizeTextRequest`, to samo co w Describe Images) → „Image with the text: …” albo „Image, plik, no text in it”. Z modelem API i przełącznikiem „Describe with the API Model” opis od modelu (1–2 zdania).
- **Decyzje:** nic nie działa bez VoiceOvera (zero kosztu dla innych). OCR domyślnie włączony, bo nic nie opuszcza urządzenia. API domyślnie wyłączone: automatyczne wysyłanie każdego mijanego obrazu na serwer to inna zgoda niż opis na żądanie; w DM dodatkowo wymaga „Use in Direct Messages”. Spoiler i media zasłonięte przez Content & Social → „Hidden image”, bez pobierania. Jeden opis na obraz na sesję (pamięć w `ImageDescriptions.shared`).
- Ustawienia: Settings → Intelligence → Accessibility.
- **Do sprawdzenia rano na iPhonie z VoiceOverem:** NAScin #ogólny, plakat „Twój plakat…” — po chwili VoiceOver powinien czytać tekst z plakatu; obraz ze spoilerem — „Hidden image”.

### 3c. Lokalne serwery (Ollama, LM Studio)

**Stan: zrobione.** Commit: `feat: local model servers over HTTP`.

- `Info.plist`: `NSAppTransportSecurity` → `NSAllowsLocalNetworking` (HTTP do `localhost`, nazw bez kropek, `.local` i adresów IP) oraz `NSLocalNetworkUsageDescription` (iOS pyta o sieć lokalną przy adresie z LAN-u; bez opisu połączenie po cichu nie działa). macOS miał już `ENABLE_OUTGOING_NETWORK_CONNECTIONS`.
- `OpenAICompatibleClient.normalizedBaseURL`: bez schematu `http://` dla adresów lokalnych (`isLocalHost`: localhost, `::1`, `.local`, nazwy bez kropek, 127/8, 10/8, 172.16/12, 192.168/16, 169.254/16), `https://` dla reszty. Wcześniej „localhost:11434” zamieniało się w `https://localhost:11434` i nie działało. 7 nowych asercji w `IntelligenceTests`.
- Stopka ustawień: porty Ollamy (11434) i LM Studio (1234), adres Maca z iPhone'a (`nazwa.local`), a przy adresie lokalnym informacja o HTTP i pytaniu iOS o sieć lokalną.
- **Ollama:** `curl localhost:11434` nie odpowiada (nie jest zainstalowana albo nie działa). **Sprawdzone zamiast tego:** prosty serwer zgodny z OpenAI w Pythonie na `localhost:8099` (skrypt w scratchpadzie sesji); w symulatorze Settings → Intelligence → API → adres `localhost:8099` → „Requests go to http://localhost:8099/v1 …” → Load Models from Server → `fake-local-model` (serwer odnotował `GET /v1/models`). Ustawienia przywrócone na koniec nocy.
- **Do sprawdzenia rano:** z iPhone'a na prawdziwą Ollamę na Macu (`nazwa-maca.local:11434`) — pytanie o sieć lokalną i odpowiedź modelu.

### 3d. Jakość w oknie 4 tys. tokenów

**Stan: zrobione.** Commit: `fix: on-device answers with tools survive a full window`.

- Budżet na urządzeniu (Ask): wcześniej 5 przypiętych + 20 ostatnich po 220 znaków, teraz 5 najnowszych + 15 najlepiej pasujących do pytania z 50 ostatnich (punkt 3a), a wyniki narzędzia `search` to 6 najbliższych pytaniu zamiast 6 najnowszych.
- `IntelligenceModel.answer(…toolbox:)` na urządzeniu nie miał tego, co ma zwykłe `respond`: limitu czasu (90 s), przyjaznych komunikatów i reakcji na przepełnienie okna. Teraz ma; przy przepełnieniu (zwykle po wynikach narzędzi) druga próba bez narzędzi na ostatnich 60% promptu (pytanie jest na końcu, więc zostaje).
- **Decyzja:** nie skracałem schematów narzędzi. Opisy i parametry już są krótkie (5 pól w `searchMessages`), a test pokazał poprawną odpowiedź; zysk z wycinania parametrów byłby mały, a model traciłby filtry.
- **Sprawdzone:** Ask w NAScin #ogólny na urządzeniu (symulator, Apple Intelligence): poprawna odpowiedź o Kite.ipa z linkiem. Ścieżki przepełnienia nie da się łatwo wywołać na tak małym kanale.

---

## Do sprawdzenia rano
1. **Mac:** kliknięcia linków w wiadomościach i Esc (punkt 1 wyżej).
2. **Mac:** Settings → Advanced → Safari Extension: stan i przycisk do ustawień Safari.
