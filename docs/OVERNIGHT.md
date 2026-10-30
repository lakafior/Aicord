# Noc 30/31.10.2026: notatki z pracy autonomicznej

Gałąź `claude/overnight-3dc9d9`, jedna sesja, symulator iPhone 18 Pro (`10C26E42…`) zalogowany na prawdziwe konto. Zapisy na koncie tylko na NAScin. Nic nie wypchnięte ani scalone.

## Podsumowanie (aktualizowane na bieżąco)

| # | Punkt | Stan |
|---|---|---|
| 1 | Etap 8: Leave Server, Invites, instrukcja Safari, link na Macu | zrobione (Mac do sprawdzenia rano) |
| 2 | Etap 7: odchudzanie `DiscordModels`, testy `Textual` | w toku |
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

## Do sprawdzenia rano
1. **Mac:** kliknięcia linków w wiadomościach i Esc (punkt 1 wyżej).
2. **Mac:** Settings → Advanced → Safari Extension: stan i przycisk do ustawień Safari.
