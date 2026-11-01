# Etap 13, Paczka 1: wiadomości systemowe, ankiety, przypięte, wątki

Notatki z sesji 1.11.2026 (gałąź `claude/pack1-system-polls-9e4515`, wycięta z `claude/components-v2-forum`).

## Wiadomości systemowe

- **Plik:** `Aicord/Common/Chat/Messages/Types/SystemMessage.swift`, `MessageCell.SystemMessage`. Wzór jak `GuildMemberJoinMessage`: ikona w kolumnie awatara, tekst z pogrubioną nazwą, godzina, opcjonalny przycisk po prawej.
- `MessageCell` kieruje do niego każdy typ poza `default`/`reply`, `chatInputCommand`/`contextMenuCommand` (wspólny widok), `guildMemberJoin` i `autoModerationAction` (to zwykła wiadomość autora z kartą AutoMod, którą już rysował `EmbedsView`). Czerwonego „Unsupported message type” już nie ma: nieznany typ to szare „<autor> · system message” z treścią, jeśli Discord ją przysłał.
- Teksty:
  - przypięcie: „X pinned a message to this channel.” + **Show Message** (`ChannelStore.jump(to:)`, doczytuje okolicę, gdy wiadomości nie ma w pamięci);
  - utworzenie wątku: „X started a thread: <nazwa>” + **Open Thread** (wątek z `message_reference.channel_id`; gdy nie ma go w `GuildStore.threads`, pobierany przez `getChannel`);
  - starter wątku (typ 21): `referenced_message` rysowana jak zwykła wiadomość; bez niej „The message this thread started from was deleted.”;
  - boost: liczba z `content` („boosted the server 3 times”), typy 9–11 dopisują „<serwer> has achieved Level N!”;
  - połączenie (typ 3): bez `ended_timestamp` „started a call.”, z nim czas (`Duration` w jednostkach), „You missed a call…”, gdy nas nie było w `participants` i to nie my dzwoniliśmy;
  - grupa: dodanie/usunięcie (cel z `mentions.first`; autor = cel → „left the group”), zmiana nazwy (`content`) i ikony;
  - obserwowanie kanału, Stage (start/koniec/mówca/ręka/temat), zamknięta ankieta (linia + karta wyniku), alerty bezpieczeństwa (36–39), nowa emoji, przypomnienie o zaproszeniu, subskrypcja roli.
- Przy okazji: wiadomość po linii systemowej tej samej osoby nie dokleja się już do niej jak kolejna linijka (warunek `inline` patrzy, czy poprzednia to `default`/`reply`).

## Ankiety

- **Widok:** `Message Body/PollView.swift`, wstawiony w `MessageBody` pod treścią (nie w kopiach z przekazań). Czyta ankietę z `channelStore.messages[id]`, a nie z przekazanej wiadomości: `DefaultMessage` jest `.equatable()` i porównuje tylko ID, edycję i embedy, więc bez tego głosy z gatewaya nie odświeżyłyby karty.
- Wyniki widać po głosie, po zakończeniu albo po „Show Results”. Wiersz: emoji (`ComponentEmoji`), tekst, „N votes”, procent, pasek. Wiele odpowiedzi: kwadraty, jedna: kółka. Stopka „N votes · Ends in 3 hours / Poll closed” i przyciski; gdy się nie mieszczą obok, schodzą pod spód (`ViewThatFits`).
- **Głos:** `PUT /channels/{c}/polls/{m}/answers/@me` z `{"answer_ids": ["1","2"]}` (tak robi klient Discorda; ID jako napisy), pusta lista cofa głos. Dodane do AicordKit: `UserAPIEndpoint.createPollVote` (id 144), `DiscordClient.createPollVote`, `Payloads.CreatePollVote`.
- **Gateway:** `ChannelStore` obsługuje `messagePollVoteAdd/Remove` (wcześniej dekodowane, ale ignorowane). Po udanym żądaniu stan własnego głosu jest ustawiany od razu (`applyOwnPollVote`), a echo z gatewaya dla nas samych niczego nie zmienia, bo `adjustPoll` sprawdza `me_voted`. Sprawdzone: po głosie na dwie odpowiedzi 1/1, 50%/50%, bez podwójnego liczenia.
- **Tworzenie:** „Create Poll” w menu „+” paska wiadomości (iOS i macOS), gdy jest uprawnienie Create Polls (w DM zawsze). `CreatePollSheet`: pytanie (300 znaków), 1–10 odpowiedzi (55 znaków), czas 1 h–2 tyg., wiele odpowiedzi. Wysyła `createMessage` z samym `poll`, bez kolejki `MessageDrainStore` (ankieta nie ma szkicu ani załączników). Emoji w odpowiedziach przy tworzeniu nie ma.

## Przypięte

- Toolbar czatu: na kanale tekstowym i ogłoszeniowym menu „…” z **Pinned Messages** i **Threads**, gdzie indziej (DM, wątek) sam przycisk z pinezką.
- `PinnedMessagesSheet` (w `ThreadBrowserSheet.swift`): `GET /channels/{id}/pins` (stary endpoint, do 50 pinów; nowy `messages/pins` z paginacją można dodać później), wiersz z autorem, datą i `MessageBody`; dotknięcie zamyka arkusz i robi `appState.open(…message:)`, czyli skok z podświetleniem.
- W menu wiadomości doszło **Pin Message / Unpin Message** (Pin Messages albo Manage Messages; w DM zawsze). Bez tego z klienta nie dało się sprawdzić linii „pinned a message”.

## Wątki

- `ThreadBrowserSheet`: segment Active / Archived, `GET /channels/{id}/threads/search?archived=…` (ten sam `searchForumThreads` co forum; działa dla zwykłych kanałów tekstowych), sortowanie po ostatniej wiadomości albo po archiwizacji, paginacja przy ostatnim wierszu, 202 = indeks w budowie (jak w forum). Wiersz to `ForumPostRow` bez tagów.
- Otwarcie: `AicordAppState.openThread(_:in:)` wkłada wątek do `GuildStore.threads` i przełącza czat. Przycisk powrotu z `ChannelContentView` działa teraz dla każdego wątku, nie tylko postów forum („Back to the channel”).

## Testy

- Buildy: `platform=macOS` i `generic/platform=iOS Simulator` (`-derivedDataPath` w scratchpadzie) przechodzą.
- Symulator iOS (iPhone 18 Pro), zapisy tylko na **NAScin #ogólny**:
  - utworzona ankieta „Pack 1 poll test: which fruit?” (Apple, Banan; wiele odpowiedzi, 24 h). Pierwsza próba padła na zerwanym połączeniu (-1005), druga przeszła;
  - głos na obie odpowiedzi → 1 vote / 50% każda, „Remove Vote” → z powrotem 0;
  - przypięta ta ankieta → linia „Lakafi pinned a message to this channel.” z Show Message; Pinned Messages pokazuje ją, dotknięcie wraca do niej w czacie. **Ankieta i pin zostały na NAScin** (można odpiąć i usunąć z menu wiadomości).
- Tylko odczyt, inne serwery: Threads w FashionReps Polska #general-offtopic → 4 zarchiwizowane wątki (archiwum, kłódka, liczba odpowiedzi), „Jak to” otwiera się w czacie z wiadomością startową i przyciskiem powrotu. NAScin i NINJACENTRAL #lobby: „No active threads.”
- Zrzuty: `side-session-notes/…/pack1-shots/` (poza repo).
- **Niesprawdzone na żywo:** Mac (UI), linie połączeń, grup, boostów, Stage, AutoMod, zamkniętej ankiety (typ 46) i utworzenia wątku, bo nie było ich w otwartych kanałach. Głos z drugiego konta (cudze głosy z gatewaya) też nie, na NAScin jest tylko jedno konto testowe.

## Otwarte

- Emoji w odpowiedziach przy tworzeniu ankiety, „Zakończ teraz” (`endPoll`) dla autora, lista głosujących na odpowiedź (`listPollAnswerVotes`).
- Nowy endpoint pinów z paginacją (`/messages/pins`), gdy kanał ma ich więcej niż 50.
- Wyszukiwanie wątków po nazwie i tworzenie wątku z wiadomości.
