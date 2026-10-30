# Noc 30/31.10.2026: notatki z pracy autonomicznej

Gałąź `claude/overnight-3dc9d9`, jedna sesja, symulator iPhone 18 Pro (`10C26E42…`) zalogowany na prawdziwe konto. Zapisy na koncie tylko na NAScin. Nic nie wypchnięte ani scalone.

## Podsumowanie (aktualizowane na bieżąco)

| # | Punkt | Stan |
|---|---|---|
| 1 | Etap 8: Leave Server, Invites, instrukcja Safari, link na Macu | zrobione (Mac do sprawdzenia rano) |
| 2 | Etap 7: odchudzanie `DiscordModels`, testy `Textual` | zrobione: −0,67 MB, 187 testów Textual (i naprawione przepełnienie stosu) |
| 3 | Etap 10: dokończenia i wyszukiwanie po sensie | czeka |
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

---

## Do sprawdzenia rano
1. **Mac:** kliknięcia linków w wiadomościach i Esc (punkt 1 wyżej).
2. **Mac:** Settings → Advanced → Safari Extension: stan i przycisk do ustawień Safari.
