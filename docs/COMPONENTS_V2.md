# Components V2 i kanały forum/media

Notatki z sesji 1.11.2026 (gałąź `claude/components-v2-forum`).

## Components V2

- **Skąd był napis:** `ComponentsV2View` w `Message Body/ComponentsV2/ComponentsV2.swift` był pustym placeholderem („ComponentsV2 unsupported”) dla każdej wiadomości z flagą `isComponentsV2`.
- **Dekoder:** `Interaction.ComponentSwitch` dekodował `[ActionRow]` z *elementu* tablicy bez klucza (zagnieżdżony `decode` w `unkeyedContainer`), więc zawsze kończył na pustym `.v2(Void)`, także dla v1. Teraz:
  - `Interaction.MessageComponent` (`AicordKit/.../Types/MessageComponent.swift`) to drzewo wszystkich typów: Action Row (1), Button (2), selecty (3, 5–8, tylko placeholder i opcje), Section (9), Text Display (10), Thumbnail (11), Media Gallery (12), File (13), Separator (14), Container (17). Nieznany typ albo błąd dekodowania jednego komponentu daje `.unknown`, a nie błąd całej wiadomości (`Lossy`).
  - `ComponentSwitch` dekoduje drzewo; jeśli na górze są same action rows i przechodzi stary dekoder, zostaje `.legacy([ActionRow])`, w przeciwnym razie `.v2([MessageComponent])`. `tree` zwraca drzewo w obu przypadkach (v1 przez konwersję).
- **Widok:** kontener to zaokrąglona karta (`tertiaryBackground`) z paskiem `accent_color` po lewej, jak embed; sekcja to tekst plus akcesorium (miniatura 85×85 albo przycisk); galeria: jedno zdjęcie w rozmiarze załącznika, więcej w siatce 2–3 kolumny, dotknięcie otwiera przeglądarkę załączników na całej galerii; plik szuka załącznika wiadomości po `attachment_id` albo nazwie z `attachment://` i używa `FileAttachmentView`; separator 8/16 pt (bez linii 8/24). Spoilery przez `SensitiveMediaCover`.
- Przy wiadomości V2 zwykła lista załączników jest ukryta: Discord pokazuje je tylko przez komponenty.
- **Interakcje:** klient nie ma żadnej wysyłki interakcji (brak `POST /interactions` w `DiscordHTTP`, przycisków v1 też nikt nie obsługiwał), więc zgodnie z zadaniem nic nowego nie wysyłam. Przyciski link otwierają URL; pozostałe przyciski i selecty są widoczne, ale wyłączone.
- Przy okazji: przyciski i menu v1 (zwykłe wiadomości botów) rysują się pod embedami tym samym widokiem.

## Kanały forum/media i inne

- **Które typy nie działały:** `ChannelButton` tagował do zaznaczenia tylko DM, grupy, tekstowe i ogłoszeniowe; reszta (`guildForum` 15, `guildMedia` 16, `guildStageVoice` 13, `guildDirectory` 14, `guildStore` 6, nowe typy) była wyszarzona z `.selectionDisabled()`, czyli martwe kliknięcie. „faq” to forum, „dodatki” i „aplikacje” to forum albo media.
- **Teraz:** każdy widoczny kanał serwera da się zaznaczyć. `ChannelContentView` w baseplate'ach wybiera: forum/media → `ForumChannelView`, typ bez czatu → `UnsupportedChannelView` z „Open in Browser” (`https://discord.com/channels/<guild>/<channel>`), reszta → `ChatView`.
- `ChannelStore` nie pobiera wiadomości dla kanałów, które nie są czatem (forum zwracało błąd do `appState.error`).
- **Lista postów:** `GET /channels/{id}/threads/search` (`UserAPIEndpoint.searchForumThreads`, `ThreadSearchQuery`, `ThreadSearchResults`). Bez `archived` zwraca aktywne i zarchiwizowane razem. `sort_by=last_message_time` (domyślnie) albo `creation_time`, `limit=25`, paginacja `offset` przy ostatnim wierszu, filtr tagów (`tag`, `tag_setting=match_some`). Odpowiedź 202 = indeks w budowie: trzy próby co 2/4/6 s i komunikat.
- Wiersz: tagi, tytuł (kłódka dla zablokowanych, pudełko dla zarchiwizowanych), autor i pierwsza linijka z `first_messages`, miniatura pierwszego obrazka, liczba odpowiedzi (`message_count`), ostatnia aktywność ze snowflake'a `last_message_id`.
- **Otwieranie posta:** wątek trafia do `GuildStore.threads` (wątków nie ma w `channels`), `getChannelStore` szuka też tam, a `appState.selectedChannel` przełącza czat. W czacie wątku forum jest przycisk powrotu do listy.
- **Uprawnienia wątku:** `PermissionsHelper.computePermissions` liczy je z nadpisań kanału nadrzędnego; Send Messages in Threads zastępuje Send Messages.

## Testy

- Buildy: `platform=macOS` i `generic/platform=iOS Simulator`.
- Symulator iOS (iPhone 18 Pro), Polish Debrid Community, tylko czytanie, nic nie wysłane:
  - „aktualizacje”: wiadomości MonitoRSS jako karty z tytułem-linkiem, miniaturą, separatorem, opisem i przyciskiem-linkiem „Więcej”.
  - Forum „aplikacje” i „konfiguracje-społeczności”: lista postów z tagami, autorem, podglądem, miniaturą, liczbą odpowiedzi i datą; filtr tagu (Nuvio pokazuje 3 posty, Kodi żadnego); otwarcie posta w czacie i przycisk powrotu do listy.
- **Pułapka:** pierwsza wersja dawała pusty czat. Media w komponentach przychodzą z `width`/`height` = 0, `aspectRatio` wychodził 0 albo ∞, a NaN w jednej komórce czyścił cały `LazyVStack`. `UnfurledMedia` zamienia teraz 0 na `nil`.

## Otwarte

- Wysyłanie interakcji (przyciski i selecty botów).
- Tworzenie posta, wyszukiwanie po nazwie, siatka dla kanałów media.
- W osobnym oknie kanału na Macu kliknięcie posta nie przełącza okna (okno ma stały kanał).
