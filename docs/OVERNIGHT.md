# Noc 30/31.10.2026: notatki z pracy autonomicznej

Gałąź `claude/overnight-3dc9d9`, jedna sesja, symulator iPhone 18 Pro (`10C26E42…`) zalogowany na prawdziwe konto. Zapisy na koncie tylko na NAScin. Nic nie wypchnięte ani scalone.

## Podsumowanie

Noc zakończona ok. 00:55: **cała lista zrobiona**, 12 commitów na `claude/overnight-3dc9d9` (od `929b10f` do `17a4c6e`), każdy z buildem iOS i macOS i testami. Na ostatnim commicie: build iOS (symulator) i macOS przechodzą, `swift test` w `AicordKit` **149** testów (było 143, +6 rankera), w `Textual` **187** (nowy target), `AicordMCP` się buduje. Nic nie scalone, nie wypchnięte, bez tagów. Commity tylko z Twoim nazwiskiem, bez Co-Authored-By.

| # | Punkt | Stan |
|---|---|---|
| 1 | Etap 8: Leave Server, Invites, instrukcja Safari, link na Macu | zrobione; poprawka kliknięć na Macu do sprawdzenia |
| 2 | Etap 7: odchudzanie `DiscordModels`, testy `Textual` | zrobione (−0,67 MB binarki; 187 testów Textual, znaleziony i naprawiony crash) |
| 3 | Etap 10: ranking, VoiceOver, lokalne serwery, okno 4K, rerankowanie, Index Channel | zrobione |
| 4 | Etap 12: workflowy wydań, AltStore, szkic Maca, wybór aktualizacji | zrobione (tylko pliki, nic nie uruchomione) |
| 5 | Etap 11: `MacBaseplate`, menu, okna kanałów, `Settings`, serwer MCP | zrobione w kodzie; na Macu nic nie było klikane |
| 6 | Language: ustawienia i polskie tłumaczenie | zrobione (780 napisów) |

Pominięte zgodnie z zadaniem: natywne listy na iPadzie, testy z drugą osobą, wideo, zrzuty do README.

**Na koncie (NAScin):** unieważnione stare zaproszenie `EdxGVcWd`. Poza tym nic nie było zapisywane ani wysyłane; na innych serwerach tylko odczyt (Leave Server tylko do alertu i Cancel na Sciwand). Lokalne ustawienia aplikacji w symulatorze przywrócone (provider Intelligence, adres testowego serwera, flaga instrukcji Safari), indeks kanału usunięty.

**Uwaga o środowisku:** `request_keep_awake` odrzucił klasyfikator trybu auto; praca mimo to przeszła do końca bez przerw.

**Najważniejsze ryzyka:** (1) zmiany interfejsu Maca (`MacBaseplate`, scena `Settings`, ⌘F, poprawka kliknięć) nie były klikane; jest wyłącznik Classic Window Layout. (2) Most MCP w aplikacji nie był sprawdzony na żywo (Debug podpisany ad hoc nie dostał się do pęku kluczy przy zablokowanym ekranie). (3) Zmiana `Codable` → `Decodable` w modelach jest szeroka; aplikacja i testy działają, ale warto przeklikać wysyłanie wiadomości z załącznikiem, ankietę i zmianę statusu (payloady zostały `Codable`, lecz to najbardziej dotknięty obszar).

---|---|---|
| 1 | Etap 8: Leave Server, Invites, instrukcja Safari, link na Macu | zrobione (Mac do sprawdzenia rano) |
| 2 | Etap 7: odchudzanie `DiscordModels`, testy `Textual` | zrobione: −0,67 MB, 187 testów Textual (i naprawione przepełnienie stosu) |
| 3 | Etap 10: dokończenia i wyszukiwanie po sensie | zrobione (ranking, VoiceOver, lokalne serwery, okno 4K, Index Channel) |
| 4 | Etap 12: przygotowanie wydań | zrobione (pliki gotowe, nic nie uruchomione) |
| 5 | Etap 11: interfejs Maca, serwer MCP | zrobione w kodzie; oba do sprawdzenia na Macu |
| 6 | Language | zrobione (ustawienia i 780 polskich napisów) |

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

### 3e. Index Channel

**Stan: zrobione.** Commit: `feat: Index Channel, a meaning index of a channel on the device`.

- `Aicord/Common/Intelligence/ChannelIndex.swift`: `ChannelIndex` (wpisy: id, data, „Nazwa: tekst” po filtrach, wektor Float32 jako `Data`), `ChannelIndexFiles` (JSON w `Application Support/ChannelIndexes/<id>.json`), `ChannelIndexSheet`.
- Budowa: wybór 500/1000/2000/5000, pobieranie po 100 z przerwą 350 ms (bezpiecznie dla limitów Discorda), postęp „Reading messages… N of M”, potem „Indexing…” (wektory), anulowanie. Tekst przez `IntelligenceSource.transcript`, więc zablokowani, filtr słów, spoilery i ukryte media nie trafiają do indeksu.
- „Add New Messages”: pobiera tylko nowsze od najnowszego w indeksie. **Decyzja:** bez automatycznej aktualizacji z gatewaya w tle w tej nocy (wymagałaby obserwatora wiadomości przy kanałach z indeksem i ostrożności z wydajnością); zapisane w ROADMAP.
- Ask About This Channel: gdy kanał ma indeks, dokłada najlepiej pasujące starsze wiadomości (pobrane ponownie przez `around`, żeby dało się je cytować i otwierać).
- **Decyzja (bez nowych paczek):** wektory z `NLContextualEmbedding` (średnia tokenów). Model Core ML byłby lepszy, ale to kilkadziesiąt–sto MB w aplikacji; zostawione jako opcja w ROADMAP.
- **Sprawdzone w symulatorze na NAScin #ogólny:** budowa 1000 → 925 wiadomości (od 13.09.2023), plik 173 kB; wyszukiwanie „kite ipa” → „Lakafi: [file: Kite.ipa]”; „Delete Index” z potwierdzeniem usuwa plik. **W symulatorze `NLContextualEmbedding` nie ma zasobów**, więc indeks był tylko słowny (arkusz to mówi). Na Macu model jest (sprawdzone w 3a), na iPhonie do sprawdzenia rano.
- Naprawione w trakcie: rozmiar „Zero kB”, bo `URL.path()` koduje spacje w „Application Support”; teraz `path(percentEncoded: false)`.

## 4. Etap 12: przygotowanie wydań

**Stan: zrobione (tylko pliki).** Commit: `ci: release workflows for iOS (AltStore) and a signed Mac draft`. Nic nie uruchomiłem na GitHubie ani nie wypchnąłem.

### Pliki
- `.github/workflows/release.yml` — tag `v*` (albo ręcznie z `workflow_dispatch`, wtedy wersja `0.0.0-<sha>` i bez wydania):
  1. `ios` (macos-26): build Release bez podpisu, `Aicord-<wersja>.ipa`, artefakt.
  2. `release` (ubuntu): `gh release create` z notatkami z najnowszej sekcji `SHIPPED.md` + link do źródła, `gh release upload` `.ipa`.
  3. `altstore-source` (ubuntu): `gh api …/releases --paginate | python3 scripts/altstore_source.py` → `site/altstore.json` + prosta `index.html`, wdrożenie na GitHub Pages (`actions/deploy-pages`).
- `.github/workflows/release_macos.yml` — szkic podpisu i notaryzacji (opis kroków w samym pliku); bez sekretu `MACOS_CERTIFICATE_P12` zadanie wypisuje notkę i nic nie robi.
- `scripts/altstore_source.py` — źródło w formacie AltStore 2 (działa też w SideStore): nazwa, ikona, opis z zastrzeżeniem o nieoficjalnym kliencie, `appPermissions.privacy` (te same opisy co w `Info.plist`, także nowe `NSLocalNetworkUsageDescription`), wersje z rozmiarem, datą, opisem i `minOSVersion` 26.0.

### Co trzeba zrobić przed pierwszym tagiem (iOS)
1. GitHub → Settings → Pages → Source: **GitHub Actions**.
2. Settings → Actions → General → Workflow permissions: „Read and write” (albo zostawić, bo workflow sam deklaruje `contents: write`, `pages: write`, `id-token: write`).
3. `git tag v0.1.0 && git push origin v0.1.0`. Źródło będzie pod `https://lakafior.github.io/Aicord/altstore.json`.
4. W AltStore/SideStore: Browse → Sources → + → ten adres.

### Sekrety dla Maca (gdy będzie płatne konto Apple Developer)
| Sekret | Skąd |
|---|---|
| `MACOS_CERTIFICATE_P12` | Pęk kluczy → certyfikat „Developer ID Application” z kluczem → eksport .p12 → `base64 -i cert.p12 \| pbcopy` |
| `MACOS_CERTIFICATE_PASSWORD` | hasło nadane przy eksporcie |
| `MACOS_TEAM_ID` | developer.apple.com → Membership |
| `NOTARY_KEY_P8` | App Store Connect → Users and Access → Integrations → Keys → nowy klucz (rola Developer) → `base64 -i AuthKey_XXX.p8` |
| `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | z tej samej strony |

Uwaga: rozszerzenie Safari na Macu też musi być podpisane Developer ID i dostać hardened runtime; eksport `developer-id` robi to dla osadzonych rozszerzeń, ale do sprawdzenia przy pierwszym przebiegu. `DEVELOPMENT_TEAM` w projekcie to dziś `5TA8RF548P`; workflow go nadpisuje sekretem.

### Mechanizm aktualizacji: API GitHuba, nie Sparkle
- **Wybór:** lekkie sprawdzanie `GET /repos/lakafior/Aicord/releases/latest` (bez tokenu, limit 60/h na IP wystarcza przy sprawdzaniu raz dziennie), porównanie z `CFBundleShortVersionString`, baner „Aicord X.Y is available” z linkiem do wydania, wyłącznik w Settings → Advanced.
- **Dlaczego:** bez nowej paczki (Sparkle to framework z XPC, własnym appcastem i kluczem EdDSA w sekretach); działa tak samo na iOS (gdzie Sparkle nie istnieje, a aktualizację i tak robi AltStore) i na Macu; nie wymaga podpisu, więc można to dodać od razu. Wada: na Macu użytkownik pobiera i podmienia aplikację sam. Jeśli Mac dostanie Developer ID i będzie dużo użytkowników, Sparkle można dodać później tylko dla macOS.
- Nie zaimplementowane tej nocy (punkt w ROADMAP).

### Ryzyka
- Workflowy nie były uruchomione; sprawdziłem tylko składnię YAML (Ruby), skrypt Pythona na danych testowych i lokalnie te same polecenia budowania (Release, `CODE_SIGNING_ALLOWED=NO`) i pakowania.
- Pierwszy build w CI bez cache potrwa (SwiftPM, DaveKit z libdave w C++); w `build_pr.yml` jest ten sam problem.
- Ikona źródła 128 px (z rozszerzenia Safari); eksport większej z `AppIcon.icon` przez Icon Composer przekroczył limit czasu.

## 5. Etap 11: Aicord dla macOS

### 5a. Interfejs Maca

**Stan: zrobione w kodzie, niesprawdzone klikaniem** (ekran Maca zablokowany). Commit: `feat(macOS): own window layout, Go menu, channel windows and Settings scene`.

Co jest w kodzie:
- `Aicord/Baseplates/MacBaseplate.swift`:
  - `MacBaseplate`: jak `LargeBaseplate`, ale z systemowym przełącznikiem paska bocznego (bez `.toolbar(removing: .sidebarToggle)` i bez własnego przycisku), pasek boczny 300–420 pt (serwery + `GuildView`/`DMsView`, czyli istniejąca natywna lista `.sidebar`), tytuł okna = `#kanał` albo nazwa rozmowy, podtytuł = serwer albo „Direct Messages”, w pasku narzędzi Search i Member List, `ContentUnavailableView` bez kanału. Inspektor członków jak dotąd, z tymi samymi `frame(minWidth: 0)` (poprawka pętli układu z Etapu 8).
  - `MacCommands`: `SidebarCommands()`, View → Show Member List ⌥⌘M, Edit → Search… ⌘F, menu **Go**: Direct Messages ⌘0, Open Channel in New Window ⇧⌘O, Mark Channel as Read ⇧⎋. Akcje idą przez `FocusedValues.macWindowActions` z aktywnego okna.
  - `ChannelWindow` + `ChannelWindowValue`: `WindowGroup("Channel", for:)` w `AicordApp`; okno z czatem i własnym inspektorem członków, arkuszami (załączniki, reakcje, Forward, Intelligence). Własny `AicordAppState(remembersSelection: false)` (nowy parametr), żeby nie nadpisywać zapamiętanego kanału głównego okna.
  - „Open in New Window” w menu kontekstowym kanału (tylko macOS).
- `AicordApp`: scena `Settings { SettingsView() }` zamiast `Window("Settings", id: "settings")`; polecenie ⌘, i zębatka w `ProfileBar` używają `openSettings`.
- Settings → Advanced (tylko Mac): **Classic Window Layout** przywraca `LargeBaseplate`.
- **Sprawdzone:** build macOS i iOS; aplikacja Debug na Macu uruchomiona z terminala działała 20 s bez awarii (bez zrzutów, ekran zablokowany).

**Do sprawdzenia rano na Macu, po kolei:**
1. Start: pasek boczny z serwerami i kanałami, tytuł okna `#kanał` i podtytuł z serwerem; systemowy przycisk paska bocznego w lewym górnym rogu chowa i pokazuje pasek (także View → Hide Sidebar, ⌃⌘S).
2. Przycisk listy członków w pasku narzędzi i ⌥⌘M: inspektor otwiera się i zamyka; zmiana szerokości okna nie wiesza aplikacji (stary błąd pętli układu).
3. ⌘F albo lupa: arkusz Search; otwarcie wyniku zamyka arkusz i przechodzi do kanału. **Ryzyko:** ⌘F może kolidować z Find w polach tekstowych; jeśli przeszkadza, zmienić na ⇧⌘F.
4. Go → Direct Messages (⌘0); Go → Open Channel in New Window (⇧⌘O) i prawy klik na kanale → Open in New Window: nowe okno z tym kanałem, pisanie, załączniki, lista członków; zamknięcie okna i ponowne uruchomienie aplikacji: główne okno wraca na swój kanał.
5. Go → Mark Channel as Read (⇧⎋) na nieprzeczytanym kanale.
6. ⌘, i zębatka przy profilu: systemowe okno Settings (rozmiar 860×620, pasek boczny sekcji widoczny; wcześniej był tu zwykły `Window` „bo Settings” — możliwe, że z powodu rozmiaru; jeśli sekcje się ucinają, wrócić do `Window` w `AicordApp`).
7. Settings → Advanced → Classic Window Layout: powrót do starego układu i z powrotem.

### 5b. Serwer MCP (tylko odczyt)

**Stan: zrobione; pomocnik przetestowany, most w aplikacji niesprawdzony na żywo.** Commit: `feat(macOS): read-only MCP server through the running app`.

Budowa:
- **`AicordMCP/`** — osobny pakiet SwiftPM z programem `aicord-mcp` (`swift build -c release` w tym katalogu → `.build/release/aicord-mcp`). **Decyzja:** pakiet zamiast nowego targetu w `project.pbxproj`, bo nie ma zależności od aplikacji ani AicordKit (tylko Foundation i Network), buduje się sam, a ręczne dodawanie targetu do pbxproj to duże ryzyko przy niewielkim zysku. Osadzenie w `.app` (Copy Files do `Contents/Helpers`) zapisane w ROADMAP.
- Protokół MCP: `initialize` (odbija wersję protokołu klienta, `capabilities.tools`, `instructions` z ostrzeżeniem, że treść wiadomości to dane), `ping`, `tools/list`, `tools/call`, powiadomienia bez odpowiedzi, `-32601` dla nieznanych metod, `-32700` dla złego JSON. Narzędzia: `list_servers`, `list_channels(server_id)`, `list_direct_messages`, `read_messages(channel_id, limit ≤ 100)`, `search_messages(query, server_id | channel_id)`, z `readOnlyHint`.
- **Most w aplikacji** (`Aicord/macOS/Sidebar/MCPBridge.swift`, plik w grupie Sidebar, bo tam był najbliższy sąsiad w pbxproj): `NWListener` tylko na `127.0.0.1:47823`, `acceptLocalOnly`, jedna linia JSON na połączenie, klucz porównywany w stałym czasie, limit 30 wywołań na minutę, odpowiedzi przez `IntelligenceSource.transcript` (zablokowani, filtr słów, spoilery, ukryte media odpadają; widać „(N messages hidden…)”). DM-y tylko z przełącznikiem „Include Direct Messages”; kanały tylko te z View Channel i Read Message History. Startuje przy uruchomieniu aplikacji, gdy włączony (narzędzia czekają na połączenie z Discordem).
- **Decyzja o kluczu:** najpierw most zapisywał port i klucz do pliku w kontenerze aplikacji, ale macOS chroni kontenery innych aplikacji (moja powłoka dostała „Operation not permitted”, Claude Desktop dostałby pytanie o dostęp albo odmowę). Dlatego stały port i klucz w ustawieniach: „Copy Configuration for Claude” kopiuje gotowy JSON z `AICORD_MCP_TOKEN` i `AICORD_MCP_PORT`; „Reset Key” unieważnia stary. Plik zostaje jako zapas.
- Ustawienia: Settings → Advanced → MCP Server (tylko Mac), domyślnie wyłączone.

Sprawdzone:
- `aicord-mcp` przez stdio: `initialize`, `tools/list` (5 narzędzi), błąd przy niedziałającej aplikacji, `-32601`, `-32700`.
- `aicord-mcp` z podstawionym mostem w Pythonie na 47823 (ten sam protokół): argumenty przechodzą, zły klucz → „Not authorised.”.
- Aplikacji z mostem **nie** udało się sprawdzić: Debug podpisany ad hoc najpewniej czeka na systemowe pytanie pęku kluczy (inny podpis niż ten, który zapisał konto), a przy zablokowanym ekranie nic się nie dzieje; nasłuchu na 47823 nie było. Uruchomienia były z argumentami `-Aicord.MCP.Enabled YES -Aicord.MCP.Token …` (domena argumentów, nic nie zapisane w ustawieniach aplikacji) i każdy proces został zamknięty.

**Do sprawdzenia rano na Macu:**
1. Zbudować i uruchomić Aicord z Xcode (podpis zespołu), Settings → Advanced → Allow MCP Server.
2. `cd AicordMCP && swift build -c release && sudo cp .build/release/aicord-mcp /usr/local/bin/` (albo inna ścieżka i poprawić `command` w konfiguracji).
3. „Copy Configuration for Claude” → wkleić do `~/Library/Application Support/Claude/claude_desktop_config.json` (sekcja `mcpServers`) → restart Claude Desktop.
4. W Claude: „list my Discord servers”, potem „read the last 10 messages in NAScin #ogólny” i „search NAScin for Kite”. Sprawdzić, że DM-y są niedostępne, dopóki „Include Direct Messages” jest wyłączone.
5. Szybki test bez Claude: `printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_servers","arguments":{}}}\n' | AICORD_MCP_TOKEN=<klucz> aicord-mcp`.

## 6. Language

**Stan: zrobione.** Commit: `feat: Language settings and a Polish translation`.

- `Aicord/Common/Settings/Language/LanguageSection.swift` (zamiast „Coming Soon”):
  - **Discord Language**: picker z 32 kodami, które Discord trzyma w `localization.locale`; nazwa po swojemu i w języku czytelnika („Polski (Polish)”); nieznany kod z konta pokazywany jako dodatkowa pozycja. Zmiana idzie przez `patchUserSettings` (jak inne ustawienia konta). **Nie zmieniałem** wartości na koncie: tylko odczyt w symulatorze pokazał „Polski (Polish)”.
  - **App Language**: bieżący język aplikacji (`Bundle.main.preferredLocalizations`) i „Change in System Settings…” (iOS: `openSettingsURLString`, gdzie przy dwóch lokalizacjach pojawia się „Język”; macOS: Język i region).
- **Tłumaczenie PL:** 780 z 792 wpisów `Localizable.xcstrings`. Tłumaczenie zrobił tańszy model (Mistral Medium, przez narzędzie `delegate`, cztery paczki po ~200), ze sprawdzeniem skryptem: te same klucze, te same `%@`/`%lld`, brak `^[`. Przejrzałem próbkę 45 wpisów i poprawiłem: „Rich Presence” zostaje po angielsku (jak w Discordzie), „explicit” = „treści dla dorosłych”, „(edited)” = „(edytowano)”. Plik zapisany w formacie Xcode (ta sama kolejność, puste obiekty), więc diff to tylko dopisane `pl`.
  - Pominięte: 12 pustych/symbolicznych i wpisy z `^[…](inflect: true)` (automatyczna odmiana nie działa po polsku; trzeba wariantów liczby mnogiej).
  - Nazwy sekcji Ustawień były surowymi `String`, więc się nie tłumaczyły; teraz przez katalog. Dodane ręcznie (`extractionState: manual`): „Profile & Status”, „About Aicord”, „Discord Settings”, „Aicord Settings”, „Intelligence”.
  - `pl` dopisane do `knownRegions`.
- **Sprawdzone:** symulator uruchomiony z `-AppleLanguages (pl)` (argument startowy, nic nie zmienione w systemie): Ustawienia, karty, nazwy sekcji po polsku.
- **Znane braki:** napisy dodane w ostatnich etapach (m.in. z tej nocy) nie są jeszcze w katalogu, bo synchronizuje go dopiero build w Xcode IDE; zostaną po angielsku do czasu synchronizacji i dotłumaczenia (ROADMAP). Formy liczbowe („%lld członków”) są w jednej formie.

---

## Do sprawdzenia rano (w tej kolejności)

1. **Przejrzeć gałąź** (`git log main..claude/overnight-3dc9d9`), zwłaszcza `d247693` (modele) i `4f121b4` (Mac).
2. **iPhone, szybko:** wysłać wiadomość z obrazkiem na NAScin, edytować ją, dodać reakcję, zmienić status — sprawdzenie, że kodowanie payloadów po zmianie modeli działa (punkt 2a).
3. **Mac — interfejs** (punkt 5a, kroki 1–7): pasek boczny i tytuł okna, inspektor członków ⌥⌘M, Search ⌘F, menu Go, kanał w nowym oknie, okno Settings, Classic Window Layout.
4. **Mac — linki w wiadomościach** (punkt 1): kliknięcie zwykłego linku, linku zaproszenia, wzmianki; zaznaczanie tekstu; Esc po przewinięciu.
5. **Mac — MCP** (punkt 5b, kroki 1–5) z Claude Desktop.
6. **Mac:** Settings → Advanced → Safari Extension (stan rozszerzenia i przycisk).
7. **iPhone z VoiceOverem:** plakat w NAScin #ogólny czytany tekstem z obrazka (punkt 3b).
8. **iPhone:** Index Channel na prawdziwym urządzeniu (czy są wektory, czy wyszukiwanie po sensie działa lepiej niż po słowach) i Ask z indeksem (punkt 3e).
9. **Ollama** na Macu i połączenie z iPhone'a przez `nazwa.local:11434` (punkt 3c).
10. **Język:** otworzyć projekt w Xcode i zbudować (synchronizacja katalogu), przejrzeć polski interfejs; ustawić Aicord na polski w Ustawieniach iOS (punkt 6).
11. **Wydanie:** gdy będzie gotowe — Pages ze źródła Actions i pierwszy tag (punkt 4).
