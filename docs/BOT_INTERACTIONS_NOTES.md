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
- Komendy z menu kontekstowego: w menu wiadomości „Apps” z komendami wiadomości (typ 3, `target_id` = wiadomość) i komendami osoby dla autora (typ 2, `target_id` = autor). Indeks komend wczytuje się przy otwarciu kanału (raz na serwer na sesję), żeby menu miało je od razu.

## Bot testowy

- `tools/testbot/bot.py` (discord.py 2.7, venv poza repo) i `README.md` z instrukcją. Komendy rejestrowane tylko na NAScin (`tree.sync(guild=…)`), nigdy globalnie.
- Token czytany przy starcie ze zmiennej `DISCORD_BOT_TOKEN` albo z pliku (`AICORD_BOT_FILE`, domyślnie `~/Desktop/bot.txt`, linia po „Token”). Nigdzie nie jest wypisywany. `.gitignore`: `.env`, `*.env`, `bot.txt`.
- Jeśli bota nie ma na serwerze, loguje link OAuth (`bot applications.commands`, View Channel + Send Messages) i nic więcej nie robi.

## Testy

(uzupełniane)
