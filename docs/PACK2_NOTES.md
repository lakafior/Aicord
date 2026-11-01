# Etap 13, Paczka 2: onboarding, slash-komendy, głosówki, wydarzenia

Notatki z sesji 1.11.2026 (gałąź `claude/pack1-system-polls-9e4515`, po fast-forwardzie do main `a37d8e2`). Endpointy według docs.discord.food, tak jak robi to oficjalny klient.

## AicordKit

- `ApplicationCommandIndex.swift`: indeks komend (`applications`, `application_commands`, opcje, wybory, wartości tekst/liczba/bool), `Payloads.CreateInteraction` (typ, `application_id`, `guild_id`, `channel_id`, `session_id`, `data` z `version`/`id`/`name`/`type`/`options`/`application_command`/`attachments`, `nonce`, `analytics_location`), zdarzenia `Gateway.InteractionStatus` i `ApplicationCommandAutocompleteResponse`.
- `MemberVerification.swift`: reguły serwera i pola formularza (`TERMS`, `TEXT_INPUT`, `PARAGRAPH`, `MULTIPLE_CHOICE`), wynik zgłoszenia, `ScheduledEventRSVP`, `Payloads.UpdateOnboardingResponses`, `Payloads.SubmitMemberVerification`.
- `UserAPIEndpoint` (id 145–154): `getGuildApplicationCommandIndex`, `getChannelApplicationCommandIndex`, `getUserApplicationCommandIndex`, `createInteraction`, `updateOnboardingResponses`, `getMemberVerification`, `submitMemberVerification`, `addScheduledEventInterest`, `removeScheduledEventInterest`, `listOwnScheduledEventRSVPs`, z funkcjami w `DiscordClient+UserAPIEndpoint.swift`.
- Gateway: `INTERACTION_CREATE`, `INTERACTION_SUCCESS`, `INTERACTION_FAILURE` i `APPLICATION_COMMAND_AUTOCOMPLETE_RESPONSE` są teraz dekodowane (wcześniej przyjmowane bez danych).
- `Guild.Onboarding`: `emoji` opcji jest opcjonalne (brak emoji psuł dekodowanie całego onboardingu), `mode` opcjonalne, doszły `responses` i czasy wyświetlenia (tylko konta użytkowników).

## Onboarding i reguły serwera

- Pliki: `Aicord/Common/Guilds/ServerOnboarding.swift` (`GuildPlaces`, `GuildPlacesSection`, `OnboardingSheet`, `MemberVerificationSheet`, `ScheduledEventsSheet`).
- Nad kanałami (`GuildView`) pojawiają się wiersze: „Agree to the Server Rules” (gdy `member.pending`), „N Events” (zaplanowane albo trwające) i „Channels & Roles” (gdy serwer ma pytania). W menu serwera doszły „Events” i „Channels & Roles”.
- Channels & Roles: pytania z emoji i opisami, pojedynczy albo wielokrotny wybór, wymagane blokują Save. Zapis `PUT /guilds/{id}/onboarding-responses` z wybranymi opcjami oraz `onboarding_prompts_seen`/`onboarding_responses_seen` (czas w ms; zachowane stare, nowe z bieżącą chwilą). Pytania pokazujemy także, gdy `enabled = false`: tak jest na LimeWire i Discord też daje wtedy Channels & Roles.
- Reguły: lista reguł z numerami, przełącznik zgody, pola tekstowe i wyboru; `PUT /guilds/{id}/requests/@me` z `form_fields` i `version`. Odpowiedź `SUBMITTED` (serwer z ręczną akceptacją) zostawia arkusz z informacją, inaczej arkusz się zamyka; gateway zdejmuje `pending`.
- Automatycznie: serwer dołączony w ciągu ostatniej doby, przy pierwszym otwarciu w Aicord, otwiera najpierw reguły (gdy `pending`), a jeśli ich nie ma, onboarding z pytaniami `in_onboarding` i bez odpowiedzi. Zapamiętane w `UserDefaults` (`Onboarding.Shown.<id>`), więc tylko raz.

## Slash-komendy

- Plik: `Aicord/Common/Chat/Input/SlashCommands.swift`.
- `/` na początku pola (bez nowej linii, nie przy edycji, bez załączników) pokazuje listę nad polem. Indeks pobierany raz na serwer/DM na sesję (`SlashCommandIndex`): serwer albo kanał DM plus komendy aplikacji zainstalowanych na koncie, tylko komendy typu chat input; podkomendy i grupy spłaszczone do „/komenda grupa pod”.
- Wybór komendy zamienia pole na formularz (`SlashCommandComposer`): opcje tekstowe i liczbowe jako pola, wybory, bool, osoby (wczytani członkowie albo uczestnicy DM), kanały (z filtrem `channel_types`), role i „mentionable” jako menu. Załączniki jako opcja nie są obsługiwane (komunikat).
- Send: `POST /interactions` typ 2 z `session_id` z bieżącego połączenia gatewaya (`getSessionID()`), `nonce` ze snowflake'a; `InteractionWatcher` czeka do 10 s na `INTERACTION_SUCCESS`/`FAILURE` o tym nonce. Porażka zostawia formularz z „The application did not respond.”, sukces albo brak odpowiedzi zamyka formularz (odpowiedź bota przychodzi jako zwykła wiadomość).
- Autouzupełnianie: opcja z `autocomplete` po 350 ms przerwy wysyła typ 4 z `focused: true` i bieżącym tekstem; wybory z `APPLICATION_COMMAND_AUTOCOMPLETE_RESPONSE` (dopasowane po nonce) jako przyciski pod polem.
- Nic nie dzieje się samo: interakcja idzie tylko po Send albo wpisaniu w pole z autouzupełnianiem.
- **Pułapka:** lista w `VStack` paska miała wysokość 0 (ScrollView obok czatu nie ma własnej wysokości), stąd stała ramka `min(n × 46, 230)`.

## Głosówki

- Pliki: `Aicord/Utilities/Audio/VoiceMessageRecorder.swift` (nagrywanie, Opus, Ogg, wysyłka), `Aicord/Common/Chat/Input/VoiceMessageButton.swift` (przycisk i pasek nagrywania).
- iOS: mikrofon w miejscu przycisku wysyłania, gdy pole jest puste; przytrzymanie nagrywa, puszczenie wysyła, przesunięcie w lewo o 80 pt anuluje. VoiceOver: dwukrotne stuknięcie zaczyna i wysyła. macOS: przycisk przy polu, pasek z Send i anulowaniem.
- Format jak w oficjalnych aplikacjach: 48 kHz mono, `OpusEncoder` z AicordKit (64 kb/s, ramki 20 ms), Ogg z OpusHead (pre-skip 312) i OpusTags, strony po 50 pakietów, CRC Ogg. Fala: do 256 bajtów (szczyt ramek w przedziale, skalowany do najgłośniejszego) w base64, `duration_secs` z liczby ramek. Krótsze niż 1 s nie są wysyłane.
- Wysyłka: `POST /channels/{id}/attachments` → PUT pliku na `upload_url` → `createMessage` z samym załącznikiem (`content_type: audio/ogg`, `duration_secs`, `waveform`) i flagą `isVoiceMessage` (walidacja payloadu w AicordKit tego wymaga). Uprawnienie Send Voice Messages.
- **Pułapka:** pierwsza wersja padała (`EXC_BREAKPOINT` w `dispatch_assert_queue`): blok tapa `AVAudioEngine` zdefiniowany w klasie `@MainActor` dziedziczył izolację, a Swift 6 sprawdza ją w czasie działania na wątku audio. Tap jest teraz instalowany z funkcji `nonisolated`.

## Wydarzenia

- `ScheduledEventsSheet`: zaplanowane i trwające, od najbliższych; obrazek (`cdn…/guild-events/<id>/<hash>.png`), „Live Now” albo data i godzina, koniec, opis, miejsce (kanał głosowy/Stage otwiera kanał, link otwiera przeglądarkę, inne miejsce jako tekst), liczba zainteresowanych.
- „Interested” od razu zmienia stan i licznik, `PUT`/`DELETE /guilds/{g}/scheduled-events/{e}/users/@me`; przy błędzie wraca. Własne zainteresowania z `GET /users/@me/scheduled-events?guild_ids=…`.

## Testy

- Buildy `platform=macOS` i `generic/platform=iOS Simulator` przechodzą (`-derivedDataPath` w scratchpadzie), `swift build` AicordKit też.
- Symulator iOS (iPhone 18 Pro). Zapisy tylko na **NAScin #ogólny**:
  - `/` → lista: na NAScin nie ma botów, jest tylko `/wordle` (aplikacja Wordle zainstalowana na koncie); wybór otwiera formularz, Send → `POST /interactions` przeszło i formularz się zamknął (Wordle odpowiada uruchomieniem Activity, której Aicord nie pokazuje).
  - Głosówka: przytrzymanie mikrofonu ~3,5 s → pasek z czasem i poziomem → wiadomość głosowa na NAScin z falą i 00:02 (pierwsza sekunda to start silnika audio). **Wiadomość została na NAScin.**
- Tylko odczyt, bez zapisu: LimeWire (konto ma `pending`) → „Agree to the Server Rules”, arkusz z regułami i wyłączonym Submit, anulowany; Channels & Roles na LimeWire (onboarding wyłączony, pytania są) i wiersz na Polish Debrid; Events na LimeWire → pusty stan.
- Przy okazji: jedno stuknięcie trafiło w kanał głosowy „Ogólne” na NAScin (zmieniona kolejność kategorii); rozłączone od razu przyciskiem w pasku połączenia.
- Zrzuty: `side-session-notes/…/pack2-shots/`.

## Czego nie dało się sprawdzić na NAScin

- Komenda bota z opcjami i autouzupełnianiem: na NAScin nie ma bota (tylko `/wordle` bez opcji). Wystarczy dodać tam dowolnego bota z komendami.
- „Interested” i lista z danymi: NAScin nie ma wydarzeń, a Aicord ich nie tworzy. Można utworzyć wydarzenie w oficjalnym kliencie na NAScin i przeklikać.
- Zapis Channels & Roles i zgoda na reguły: NAScin nie ma onboardingu ani reguł; na innych serwerach tylko podgląd. Automatyczne otwarcie po dołączeniu niesprawdzone (wymaga dołączenia do nowego serwera).
- Mac: nagrywanie przyciskiem i pasek Send, lista komend i formularz.

## Otwarte

- Modale i komponenty w odpowiedziach na komendy (`INTERACTION_MODAL_CREATE`), opcje typu załącznik, komendy z menu kontekstowego (osoba/wiadomość).
- Odświeżenie indeksu komend po `GUILD_APPLICATION_COMMAND_INDEX_UPDATE` (dziś raz na sesję).
- Tworzenie wydarzeń, wydarzenia cykliczne (wyjątki), zdarzenia gatewaya wydarzeń (lista odświeża się przy otwarciu).
