# Messages pack: notatki

Forward, foldery Requests i Spam, zaproszenia do znajomych oraz skok do wiadomości z Search. Praca autonomiczna z 30.10.2026 na gałęzi `claude/messages-pack-00ce9f`. Tu są decyzje z uzasadnieniem, stan i lista rzeczy do kliknięcia przez użytkownika.

## Stan

| Funkcja | iOS | macOS | Sprawdzone na żywo |
|---|---|---|---|
| Forward (wybór celu, komentarz, wysyłka) | tak | tak (ten sam arkusz) | wysyłka z NAScin #ogólny na NAScin #ogólny, w symulatorze |
| Wyświetlanie przekazanych wiadomości ze źródłem | tak | tak | w symulatorze; stuknięcie w źródło otwiera oryginał |
| Folder Requests | tak | arkusz z paska DM | lista na prawdziwym koncie jest pusta; wygląd i akcje na danych testowych |
| Folder Spam | tak | arkusz z paska DM | 2 prawdziwe wiadomości, tylko oglądane (iOS i Mac) |
| Friends: Incoming / Sent, badge | tak | arkusz z paska DM | prawdziwe konto nie ma zaproszeń; wygląd i Accept na danych testowych |
| Search: skok do wiadomości z podświetleniem | tak | tak (arkusz) | na NAScin, iOS i Mac |
| Search: daty od–do, regex | tak | tak | na NAScin w symulatorze |

Buildy: macOS (arm64) i iOS (symulator) bez nowych ostrzeżeń. PaicordLib: 111 testów (było 102, doszło 9).

## Commity

1. `feat(lib)`: endpointy próśb o wiadomość, stan spamu, testy forward.
2. `feat`: Forward, źródło przekazanej wiadomości, skok do wiadomości (`ChannelStore.jump(to:)`).
3. `feat(search)`: wyniki wiadomości otwierają kanał na tej wiadomości, daty i regex.
4. `feat(messages)`: foldery Requests i Spam, zakładki zaproszeń, skróty na Macu i iPadzie.
5. `fix`: poprawki po testach w symulatorze i na Macu.
6. `docs`: te notatki, ROADMAP, README.

## Decyzje

### Forward

- **Modele były już w PaicordLib** (`MessageReference.Kind.forward`, `MessageSnapshot`, walidacja w `CreateMessage`), więc doszły tylko testy: kodowanie `message_reference` typu 1 i dekodowanie wiadomości z `message_snapshots` i flagą `HAS_SNAPSHOT`.
- **Komentarz jako osobna wiadomość po forwardzie.** Tak robi oficjalny klient. docs.discord.food nie mówi jasno, czy `content` może iść w tym samym żądaniu co forward, więc nie ryzykowałem odrzucenia całego forwardu.
- **Do pięciu celów naraz** (limit Discorda). Cele, które się nie udały, zostają zaznaczone, a błąd jest pod podglądem, więc „Send” ponawia tylko je.
- **Lista celów**: DM-y i grupy od najnowszych (bez próśb i spamu), a kanały tekstowe tylko z bieżącego serwera, dopóki nie wpiszesz nic w wyszukiwarkę. Wyszukiwanie obejmuje wszystkie serwery (dopasowuje też nazwę serwera, więc „NAScin” pokazuje jego kanały).
- **Uprawnienia** (View Channel + Send Messages) sprawdzam tylko na serwerach, które mają już `GuildStore` z Twoimi rolami. Nie tworzę `GuildStore` dla każdego serwera, bo to subskrypcja gatewaya (op 37) na każdy z nich. Na pozostałych odpowie Discord, a błąd pokaże się w arkuszu.
- **Forward w menu**: tylko dla wiadomości typu default/reply, bez ankiety, połączenia i komponentów v2. `components` w PaicordLib dekoduje puste `[]` jako `.v2` (zagnieżdżony `decode([ActionRow])` w kontenerze bez klucza), więc sprawdzam tylko flagę `isComponentsV2`. Błąd dekodera naprawiony razem z Components V2 (`docs/COMPONENTS_V2.md`).
- **Wyświetlanie**: istniejący blok „Forwarded” dostał linię źródła (#kanał · serwer albo nazwa DM, data oryginału). Stuknięcie otwiera oryginał, jeśli jesteś na tym serwerze lub w tej rozmowie. Kopia nie pokazuje reakcji oryginału, bo ma jego ID i wcześniej brała reakcje z `ChannelStore.reactions`.

### Skok do wiadomości (Search i źródło forwardu)

- `PaicordAppState.open(guild:channel:message:)` ustawia `pendingJump`, a `ChatView` po otwarciu kanału wywołuje `ChannelStore.jump(to:)`.
- Jeśli wiadomość jest już wczytana, czat tylko przewija. Jeśli nie, wczytane wiadomości zastępuje 50 wiadomości wokół niej (`around`), a `hasLatestMessages` przechodzi na `false`. Strzałka w dół wczytuje wtedy najnowsze (`returnToLatest()`), a nie tylko przewija. Czat nie ma dziś przewijania historii w górę (`PlaceholderMessageSet` jest zakomentowany), więc to był jedyny sensowny sposób.
- Przewinięcie jest wysyłane dwa razy (drugi raz po 250 ms), bo po wczytaniu nowych wiadomości `ScrollView` wraca na swoją kotwicę `.bottom`. Wiadomość ląduje na dole widoku, nie na środku: `scrollPosition(id:anchor:)` ma jedną kotwicę dla całego czatu.
- Podświetlenie: tło w kolorze akcentu i pasek z lewej przez 4 s.

### Requests i Spam

- **Źródło danych**: prośby i spam to zwykłe kanały DM z flagami `is_message_request`, `is_spam` albo flagą kanału `IS_SPAM` (`1 << 5`). Przychodzą w READY i zmieniają się przez Channel Update/Delete. Nowe `DiscordChannel.isPendingMessageRequest` i `isSpam`.
- **Endpointy** (docs.discord.food): akceptacja `PUT /channels/{id}/recipients/@me` z `consent_status: 2`, odrzucenie `DELETE` tego samego, zbiorczo `PUT /channels/recipients/@me/batch-reject` (do 50), podgląd pierwszej wiadomości `GET /users/@me/message-requests/supplemental-data?channel_ids=…` (do 25).
- **Spam**: Discord nie ma osobnego endpointu „to nie spam”. Oficjalny klient przenosi wiadomość ze spamu przez akceptację, więc „Not Spam” to ta sama akceptacja. „Delete” to odrzucenie (usuwa kanał po Twojej stronie).
- **„Ignore”** przy prośbie to `PUT /users/@me/relationships/{id}/ignore` (endpoint już był). Prośba znika z listy i z licznika, a lista ma zwijaną sekcję „Ignored” z „Unignore”. Działa tylko w DM jeden na jeden: w grupie nie ma jednej osoby do zignorowania.
- **Przełączniki z Content & Social nie ukrywają folderów.** One decydują, gdzie Discord kieruje nowe wiadomości, a to, co już jest w Requests lub Spam, powinno być widoczne.
- **Rozmowa z prośbą lub spamem**: zamiast pola wiadomości jest pasek Reject/Ignore/Accept (Delete/Not Spam), bo odpowiedź oznaczałaby akceptację. Nie ma też przycisku połączenia, żeby nie dzwonić do obcych.
- **Badge zakładki Messages** nie liczy wzmianek z próśb ani ze spamu. Prośby mają własny licznik w wierszu folderu.
- `CurrentUserStore` obsługuje teraz Channel Update dla kanałów prywatnych. Wcześniej akceptacja prośby z innego klienta nie przenosiła rozmowy.

### Zaproszenia do znajomych

- Arkusz Friends ma trzy zakładki: Friends / Incoming / Sent. Otwiera się na Incoming, gdy czeka zaproszenie.
- Akceptacja: `PUT /users/@me/relationships/{id}` z pustym ciałem. Domyślny typ (-1) akceptuje istniejące zaproszenie, a nie wysyła nowego. Odrzucenie przychodzącego i anulowanie wysłanego: `DELETE` (oba za potwierdzeniem). Przycisk przy przychodzącym nazywa się „Ignore”, jak w Discordzie, ale to zwykłe usunięcie zaproszenia, a nie ignorowanie użytkownika.
- Badge (przycisk Friends na iPhonie, wiersz Friends na Macu) liczy przychodzące, bez zignorowanych i oznaczonych przez Discorda jako spam (`is_spam_request`). Te są w osobnej sekcji „Ignored or Likely Spam”.
- **Na żywo**: `RELATIONSHIP_ADD/UPDATE/REMOVE` były już obsłużone w `CurrentUserStore`, a widok czyta stamtąd, więc lista i badge zmieniają się same. `RELATIONSHIP_ADD` uzupełnia teraz też pamięć podręczną użytkowników.

### Search

- Daty idą do Discorda jako `min_id`/`max_id` (snowflake z początku dnia „od” i z początku dnia po „do”, więc oba dni się liczą). Nowe pola w `MessageSearchQuery` i `MessageSearchQuery.boundary(for:)`.
- Regex działa w aplikacji na wynikach, które przysłał Discord (Swift `Regex`, opcjonalnie bez wielkości liter). Nagłówek pokazuje „N of M loaded”, a „Show More” doładowuje kolejne strony. Sam regex bez tekstu wysyła zapytanie bez `content`, czyli najnowsze wiadomości w zakresie.
- Pasek z menu filtrów znika podczas wpisywania, więc „Dates and Regex…” jest też wierszem nad wynikami.

### macOS i iPad

- Na Macu i iPadzie nie ma zakładek Messages i Search, więc nad listą DM-ów są cztery skróty: Friends (z plakietką), Search, Message Requests (z licznikiem), Spam. Każdy otwiera arkusz z tym samym widokiem co na iPhonie.
- Root alert błędów nie pokazuje się nad arkuszem, więc arkusze mają własny `sheetErrorAlert()`.

## Testy na prawdziwym koncie (co zrobiłem)

- Forward: jedna wiadomość („test accord…”) z NAScin #ogólny na NAScin #ogólny, z komentarzem „Accord forward test” (pierwsza litera zginęła przy wpisywaniu w symulatorze). Nic nie poszło nigdzie indziej. Na NAScin zostały te dwie nowe wiadomości; usuń je, jeśli przeszkadzają.
- Spam (2 prawdziwe wiadomości): lista, podgląd i otwarta rozmowa z paskiem wyboru, bez klikania akcji.
- Requests i Incoming/Sent: prawdziwe konto ich nie ma. Wstrzyknąłem lokalnie (tymczasowy kod, usunięty przed commitem) prośbę z kanałem `11` oraz zaproszenia od użytkowników `1`, `2`, `3`. Takie ID nie istnieją, więc nic nie mogło trafić do prawdziwych osób. „Accept” prośby wysłał `PUT /channels/11/recipients/@me`, a Discord odpowiedział 404 z nagłówkiem `x-discord-features: message-requests`, czyli endpoint jest właściwy. Aplikacja pokazała błąd i zostawiła prośbę. „Accept” zaproszenia `1` też dostał 404, a wiersz został.
- Na czas testów wyłączyłem lokalnie (UserDefaults symulatora, nie konto) banery powiadomień w aplikacji, bo zasłaniały pasek; po testach przywróciłem wartość domyślną.
- Ustawień konta nie zmieniałem.

## Do sprawdzenia przez użytkownika

Z prawdziwymi danymi, bo tego nie wolno mi było klikać:

1. **Prośba o wiadomość.** Poproś kogoś bez wspólnej przyjaźni (albo drugie konto) o DM, który trafi do Messages → Message Requests. Sprawdź podgląd pierwszej wiadomości. Potem kolejno:
   - otwórz rozmowę i kliknij **Accept**: rozmowa powinna przejść do zwykłych wiadomości i dostać pole wpisywania;
   - przy innej prośbie przesuń w lewo i kliknij **Ignore**: prośba znika z listy i ląduje w sekcji „Ignored”; potem **Unignore**;
   - **Reject** (przesunięcie albo pasek w rozmowie, z potwierdzeniem): prośba znika.
2. **Spam**: Messages → Spam. Na jednej wiadomości **Not Spam**: powinna trafić do zwykłych rozmów. Na drugiej **Delete**: znika. „Delete All” u góry (na Macu w pasku arkusza) usuwa wszystkie po potwierdzeniu.
3. **Zaproszenia**: z drugiego konta wyślij zaproszenie. Badge na przycisku Friends powinien pokazać 1 bez odświeżania. Zakładka Incoming: **Accept** (osoba przechodzi do Friends) albo **Ignore** (z potwierdzeniem). Potem wyślij zaproszenie z oficjalnej aplikacji (Aicord nie ma jeszcze „Add Friend”): pojawi się w zakładce Sent, gdzie sprawdź **Cancel Request**.
4. **Forward do DM** albo do kilku celów naraz. Ja wysyłałem tylko na NAScin.
5. **Forward na Macu** z menu kontekstowego (prawy przycisk). Arkusz jest ten sam co na iOS, ale wysyłki z Maca nie sprawdzałem.
6. **Prośba zaakceptowana w oficjalnej aplikacji** powinna od razu zniknąć z Requests w Aicordzie (Channel Update).

## Ryzyka i znane braki

- `consent_status` i pusty `PUT` relacji są z dokumentacji, nie z prawdziwej akceptacji. 404 na fałszywych ID potwierdza tylko ścieżki.
- Po akceptacji prośby zakładam, że Discord zwraca kanał z `is_message_request: false`. Dla pewności i tak czyszczę te flagi lokalnie.
- Skok do wiadomości zastępuje wczytane wiadomości kanału. Wiadomości z gatewaya przychodzące w tym czasie nie są dopisywane, dopóki nie wrócisz strzałką do najnowszych (tak działało już `hasLatestMessages`).
- Filtr uprawnień w arkuszu Forward działa tylko na serwerach z wczytanym `GuildStore`. Na innych mogą być widoczne kanały, w których nie wolno pisać; Discord wtedy odmówi.
- Błędy z Discorda pokazują się w surowej formie (`DiscordHTTPError.badStatusCode(...)`), jak w reszcie aplikacji.
- ~~Dekoder `Interaction.ComponentSwitch` w PaicordLib myli puste `components` z v2.~~ Naprawione razem z Components V2.
