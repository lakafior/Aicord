# Interakcje z botami i bot testowy

Notatki z sesji 1.11.2026 (gałąź `claude/bot-interactions-361499`). Endpointy według docs.discord.food, tak jak wysyła je oficjalny klient.

## AicordKit

- `MessageComponent.Select` ma teraz wszystko, czego trzeba do wysłania wyboru: `type` (3 string, 5 osoba, 6 rola, 7 mentionable, 8 kanał), `custom_id`, `min_values`/`max_values`, `channel_types`, `default_values`. Dekoder v2 i konwersja z v1 (`ActionRow`) wypełniają je tak samo.
- `InteractionModal.swift`:
  - `Gateway.InteractionModalCreate` (`INTERACTION_MODAL_CREATE`, wcześniej przyjmowane bez danych): `id`, `nonce`, `channel_id`, `custom_id`, `title`, aplikacja i pola.
  - `Gateway.ModalField`: stary format (action row z text inputem) i nowy (label typ 18 z text inputem albo selectem, opis), tekst (typ 10); inne typy, np. upload pliku, jako `unsupported`. Dekodowanie stratne, jak w komponentach.
  - `Payloads.ComponentInteraction` (typ 3: `message_id`, `message_flags`, `data.component_type`, `custom_id`, `values`) i `Payloads.ModalSubmitInteraction` (typ 5: `data.id` modala, `custom_id`, odpowiedzi w tym samym kształcie, w jakim przyszły: wiersz typ 1 albo label typ 18).
- `createInteraction` ma przeciążenia dla obu payloadów.
- `CreateInteraction.CommandData`: `target_id` (komendy z menu kontekstowego) i `attachments` jako `UploadedAttachment` (`id`, `filename`, `uploaded_filename`) zamiast pustej tablicy napisów.

## Aicord

- `BotInteractions` (`Message Body/ComponentsV2/BotInteractions.swift`):
  - Klik w przycisk albo wybór w menu wysyła `POST /interactions` typ 3 z `session_id` bieżącego połączenia gatewaya i `nonce` ze snowflake'a. `application_id` z wiadomości, a gdy go nie ma, ID autora (bot).
  - Przycisk w trakcie pokazuje kółko zamiast etykiety, menu kółko zamiast strzałki; drugi klik w tym czasie nic nie wysyła.
  - `INTERACTION_FAILURE` (Discord wysyła je, gdy bot nie odpowie w 3 s) daje pod wiadomością czerwone „This interaction failed”; błąd HTTP pokazuje swój opis. Sukces albo brak zdarzenia w 10 s nic nie pokazuje: odpowiedź bota przychodzi jako zwykła wiadomość albo edycja.
- Menu wyboru: arkusz z listą (wyszukiwanie, emoji, opisy). Przy jednym wyborze dotknięcie od razu wysyła, przy kilku są znaczniki i Done (aktywne od `min_values`). Osoby to wczytani członkowie serwera (plus ty), role z serwera, kanały filtrowane po `channel_types`. Wybrane etykiety zostają w menu, dopóki bot nie zmieni wiadomości.
- Przyciski premium są wyłączone (sklep), link otwiera URL jak wcześniej.
- Modal: `InteractionWatcher` łapie `INTERACTION_MODAL_CREATE` i zapamiętuje, gdzie poszła interakcja o tym `nonce` (aplikacja, serwer, kanał). `ChatView` tego kanału pokazuje `InteractionModalSheet`: formularz z polami tekstowymi (krótkie i akapit, placeholder, licznik `max_length`, wartość domyślna), selectem (Picker albo przełączniki przy kilku wartościach) i tekstem. Submit nieaktywny, dopóki brakuje wymaganych pól. Wysyłka typ 5; porażka zostawia arkusz z „The application did not respond.”.
- Stopka wiadomości (`InteractionFooter`): flaga `loading` (odpowiedź odroczona) daje kółko i „<bot> is thinking…”, flaga `ephemeral` „Only you can see this • Dismiss message” (Dismiss usuwa wiadomość lokalnie, tak jak Discord).
- `DefaultMessage` i `ChatInputCommandMessage` porównują teraz też komponenty, flagi i treść, inaczej update z przycisku (bez `edited_timestamp`) nie odświeżał komórki.
- Slash-komendy: opcja typu załącznik. „Choose File…” (`fileImporter`), przed Send plik idzie na `POST /channels/{id}/attachments` i PUT na `upload_url`, a interakcja ma `data.attachments` i wartość opcji równą indeksowi.
- Forum (`ForumChannelView.swift`): w pasku „New Post” (gdy jest Send Messages) otwiera `NewForumPostSheet`: tytuł (do 100 znaków), treść, do 5 tagów (moderowane tylko z Manage Threads), wymagany tag, gdy forum ma flagę `REQUIRE_TAG`. Wysyłka `POST /channels/{id}/threads` (`startThreadInForumOrMediaChannel`, było w AicordKit), po sukcesie post otwiera się w czacie. Pole wyszukiwania nad listą wysyła `name` w `threads/search` (już obsługiwane przez `ThreadSearchQuery`) po 350 ms przerwy.
- Komendy z menu kontekstowego: w menu wiadomości „Apps” z komendami wiadomości (typ 3, `target_id` = wiadomość) i komendami osoby dla autora (typ 2, `target_id` = autor). Indeks komend wczytuje się przy otwarciu kanału (raz na serwer na sesję), żeby menu miało je od razu.

## Bot testowy

- `tools/testbot/bot.py` (discord.py 2.7, venv poza repo) i `README.md` z instrukcją. Komendy rejestrowane tylko na NAScin (`tree.sync(guild=…)`), nigdy globalnie.
- Token czytany przy starcie ze zmiennej `DISCORD_BOT_TOKEN` albo z pliku (`AICORD_BOT_FILE`, domyślnie `~/Desktop/bot.txt`, linia po „Token”). Nigdzie nie jest wypisywany. `.gitignore`: `.env`, `*.env`, `bot.txt`.
- Jeśli bota nie ma na serwerze, loguje link OAuth (`bot applications.commands`, View Channel + Send Messages) i nic więcej nie robi.

## Pułapki znalezione w testach

- **Indeks komend serwera się nie dekodował,** gdy jakiś bot miał komendę z menu kontekstowego: te komendy nie mają w indeksie `description`, a `Command.description` było wymagane. Cały indeks serwera wypadał i na liście był tylko `/wordle` z konta. Teraz `description` jest opcjonalne. Błąd był też przed tą sesją, na każdym serwerze z takim botem.
- **„Unknown Integration” (10005)** przy komendzie bota zarejestrowanej na serwerze: `data` musi mieć `guild_id` komendy, inaczej Discord szuka komendy globalnej. `CommandData` bierze je z komendy.
- **`required: false` znika w `INTERACTION_MODAL_CREATE`,** a `true` przychodzi. Brak pola znaczy więc „nie wymagane” (odwrotnie niż domyślne w dokumentacji), inaczej Submit był zablokowany przez opcjonalne pole.
- `DefaultMessage`/`ChatInputCommandMessage` są `Equatable`: bez porównania komponentów, flag i treści update z przycisku nie odświeżał komórki.
- Rola `@everyone` miała podwójne `@` w listach ról (menu i slash-komendy).
- Menu wewnątrz kontenera V2 zlewało się z tłem karty; ma teraz obrys.
- W symulatorze banery Aicord Alerts (słowa kluczowe) wjeżdżają na pasek narzędzi arkuszy. Jedno stuknięcie w Submit trafiło w baner i otworzyło inny serwer (nic tam nie wysłane); trzeba patrzeć przed stuknięciem u góry ekranu.

## Testy

Buildy `platform=macOS` i `generic/platform=iOS Simulator` (derived data w scratchpadzie) bez nowych warningów. Symulator iPhone 18 Pro, konto użytkownika, wszystko tylko na **NAScin #ogólny**; bot `Bot_test` uruchomiony lokalnie na czas testów i potem wyłączony. Bota dodał użytkownik linkiem OAuth (View Channel + Send Messages).

| Funkcja bota | Wynik |
|---|---|
| Lista `/` | 13 komend bota obok `/wordle` (po poprawce indeksu) |
| `/options`: string z choices, integer, number, boolean, user, channel, role, mentionable, attachment | wszystko doszło: `text: Cherry, count: 42, ratio: 0.5, flag: True, who, where, role, target, file: aicord-test.txt (30 B)`; plik z „On My iPhone”, pierwsza próba padła na uploadzie (-1005, sieć symulatora), druga przeszła |
| `/fruit` (autouzupełnianie) | „Ap” → Apple, Apricot, Grape; wybór → „You picked apricot.” |
| `/group nested gamma` (grupa i podkomenda) | „flag: True” |
| `/buttons`: primary, secondary, success, danger, link, disabled | wszystkie style; link ze strzałką, Disabled wyszarzony |
| Update (edit_message) | „clicked 1×”, „(edited)” |
| Ephemeral | „Only you can see this • Dismiss message”; Dismiss usuwa wiadomość |
| Think (defer + follow-up) | „Bot_test is thinking…”, po 4 s follow-up |
| No reply | „This interaction failed” pod wiadomością, znika przy następnym kliknięciu |
| Defer update | treść zmieniona po 2 s |
| Modal (przycisk, `/modal`, przycisk w V2) | arkusz z polami (action row) i menu (label); Submit nieaktywny bez wymaganych; odpowiedź z wartościami |
| `/selects`: string (1–2), user, role, mentionable (do 3), channel (tylko tekstowe) | arkusze z listą; multi z Done; bot odpisał wybrane wartości |
| `/v2`: kontener, sekcja z przyciskiem, separator, select, przyciski | „Clicks: 1”, „Size: medium” |
| `/ephemeral` z przyciskami | Update na wiadomości ephemeral działa (`message_flags` 64) |
| `/defer` | „thinking…”, odpowiedź i ephemeral follow-up |
| `/edit` | „Original reply…” → „Edited reply.” |
| `/silent` | formularz zostaje z „The application did not respond.” |
| Apps → Inspect user / Quote message | odpowiedź ephemeral z ID bota; cytat wiadomości w kanale |

Zrzuty: `side-session-notes/…/bot-interactions-shots/`.

Niesprawdzone: nowy post i wyszukiwanie w forum (NAScin nie ma kanału forum, a tworzenie go wymaga serwera społeczności), wszystko na Macu (tylko buildy).

**Zostało na NAScin:** wiadomości bota z testów (przyciski, menu, V2, odpowiedzi, cytat). Dwie odpowiedzi bota wspomniały rolę Notifiarr i @Lakafi (wybrane w menu), zanim bot dostał `allowed_mentions` bez pingów. W ankiecie „Pack 1 poll test” widać głos na Apple, którego ta sesja nie oddawała (stuknięcia były tylko w pole wiadomości).
