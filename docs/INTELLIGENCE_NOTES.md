# Intelligence (Etap 10): notatki

Gałąź `claude/intelligence-5f310a`. Praca autonomiczna, commity podpisane tylko użytkownikiem.

## Stan

- **Faza 1: zrobiona i sprawdzona** na macOS (prawdziwe konto) i iOS (symulator iPhone 18 Pro).
- **Faza 2: zrobiona w całości**, większość sprawdzona na żywo (szczegóły i braki w sekcji „Faza 2”).
- Buildy iOS (symulator) i macOS przechodzą. `swift test` w `AicordKit`: **143 testy** (110 + 33 nowe), 0 błędów.
- **Klucz testowy API usunięty** przyciskiem „Remove Key” na Macu; `security find-generic-password -s net.smigi.aicord.intelligence` nic nie znajduje. W symulatorze klucza nigdy nie wpisywałem (baza pęku kluczy symulatora: 0 wpisów tej usługi). Klucz nie trafił do repo, kodu, testów, commitów ani notatek. Dostawca na Macu przestawiony z powrotem na „On This Device”.

## Co jest zrobione (faza 1)

### Ustawienia → Intelligence (`Aicord/Common/Settings/Intelligence/IntelligenceSection.swift`)
- Nowa zakładka w grupie „Aicord Settings”, ikona `sparkles`.
- **Dostawca:** „On This Device” (domyślnie) albo „OpenAI-Compatible API”.
  - Na urządzeniu: `SystemLanguageModel.default.availability` pokazane wprost: „Apple Intelligence is ready” albo powód (urządzenie nie obsługuje, Apple Intelligence wyłączone, model się pobiera) z podpowiedzią, co zrobić.
  - API: adres (normalizowany: dopisuje `https://`, ucina wklejone `/chat/completions`, dopisuje `/v1`, gdy w ścieżce nie ma wersji), klucz w **pęku kluczy** (`kSecClassGenericPassword`, usługa `net.smigi.aicord.intelligence`, `AfterFirstUnlockThisDeviceOnly`), po zapisie pole pokazuje tylko „Saved in Keychain” i przycisk „Remove Key”. Model: pole tekstowe plus „Load Models from Server” (`GET /models`) z listą do wyboru. „Context Size” 8K / 32K / 128K. „Test Connection” wysyła jedno krótkie zapytanie bez treści z Discorda.
  - Zewnętrzne API nie działa, dopóki nie ma adresu i modelu (funkcje pokazują „Add the API address and model…”).
- **Prywatność:** „Use in Direct Messages” domyślnie wyłączone. Każdy arkusz ma na dole notkę, dokąd idą dane („Runs on this device. Nothing leaves it.” albo „Messages are sent to api.mistral.ai.”).
- „Summary Language”: język aplikacji albo wybrany z preferowanych języków systemu.

### Tłumaczenie (`Aicord/Common/Intelligence/MessageTranslation.swift`)
- Framework **Translation**, bez modelu językowego. Język wiadomości wykrywa `NLLanguageRecognizer` (pewność > 0,5).
- „Translate” w menu wiadomości (`EntityContextMenu.swift`, sekcja z „Copy Text”). Tłumaczenie pojawia się **pod treścią** z paskiem w kolorze akcentu i stopką „Translated from English · Show Original”. „Show Original” usuwa tłumaczenie; w menu jest wtedy „Show Original” zamiast „Translate”.
- Gdy para języków jest pobrana: `TranslationSession(installedSource:target:)` od razu. Gdy nie: `.translationTask`, który pokazuje systemowy arkusz pobierania.
- Ustawienia: „Translate To” (język aplikacji albo dowolny obsługiwany) i „Translate Automatically” (lista języków). Automatyczne tłumaczenie działa tylko dla par **już pobranych**, żeby nie wyskakiwał arkusz pobierania przy przewijaniu. Zamknięte automatyczne tłumaczenie nie wraca.
- **Decyzja:** tłumaczenie nie podlega przełącznikowi DM, bo to nie model językowy i nic nie opuszcza urządzenia (po pobraniu języka).
- **Decyzja:** tłumaczenie pod oryginałem, a nie zamiast niego, bo tak opisuje zadanie („pod treścią”); „Show Original” chowa tłumaczenie.
- Tłumaczony jest tekst z wzmiankami zamienionymi na nazwy i bez spoilerów.

### Podsumowanie kanału (`ChannelSummarySheet.swift`)
- Przycisk ✨ w pasku narzędzi czatu (obok tytułu kanału) z menu: „Catch Up on Unread” (nieaktywne bez nieprzeczytanych), „Last 100 / 500 / 1000 Messages”. W DM przycisku nie ma, dopóki „Use in Direct Messages” jest wyłączone.
- Arkusz: pasek postępu, „Cancel”, potem punkty. Pod każdym punktem przyciski „Autor · godzina” prowadzące do wiadomości (istniejący `appState.open(guild:channel:message:)`, ten sam co w Search: przewija i podświetla). „Summarize Again” w pasku.
- **Etapami** (`AicordKit/Sources/AicordKit/Intelligence/Summarizer.swift`): wiadomości jako linie `[n] Autor: tekst`, dzielone na kawałki według budżetu tokenów; każdy kawałek → do 5 punktów z numerami źródeł; potem łączenie punktów (też kawałkami, aż zostanie jedna lista). Numery są globalne, więc linki przeżywają łączenie. Gdy wszystko się mieści (API), jest jedno zapytanie.
- Budżet: na urządzeniu połowa `SystemLanguageModel.default.contextSize` (ok. 2 tys. tokenów na wiadomości, reszta na instrukcje i odpowiedź), przez API 2/3 ustawionego „Context Size”. Szacunek tokenów: znaki / 3 (ostrożnie dla polskiego). Gdy model i tak zgłosi przepełnienie, jedna ponowna próba z nowszymi 60% kawałka.
- Na urządzeniu limit 90 s na jedno zapytanie (raz model systemowy nie odpowiedział w ogóle).

### Catch Up („Co mnie ominęło”, `CatchUpSheet.swift`)
- **Decyzja (zmieniona po uwadze użytkownika):** pierwotnie przycisk ✨ nad listą serwerów, który zbierał nieprzeczytane ze wszystkich serwerów. Przy wielu serwerach to za dużo szumu, więc Catch Up jest teraz w menu po przytrzymaniu (prawym kliknięciu):
  - **serwera** → arkusz z nazwą serwera: jego nieprzeczytane kanały tekstowe i ogłoszeń (bez wyciszonych kanałów i kategorii), najnowsze najpierw, maks. 15 kanałów, ostatnie 100 nieprzeczytanych wiadomości każdego, 2–3 punkty na kanał z linkami. Kanały, których nie da się przeczytać (brak uprawnień, sklep serwera nie wczytany), są pomijane z licznikiem w stopce.
  - **kanału** → „Catch Up” (podsumowanie nieprzeczytanych tego kanału, ten sam arkusz co z ✨).
- Stuknięcie nazwy kanału otwiera kanał; przycisk źródła otwiera wiadomość.

### Filtry treści
`IntelligenceSource.transcript` pomija to, co czat ukrywa: zablokowanych i ignorowanych, wiadomości z filtrem słów (`WordFilter.hides`, z zakresem z Content & Social), spoilery (`||…||` → „[spoiler]”), załączniki i embedy z redakcją `blur`/`block` (`MediaFilter`). Licznik pominiętych jest w stopce arkusza. Z załączników model widzi tylko „[image: opis/nazwa]”.

### Biblioteka i testy (`AicordKit/Sources/AicordKit/Intelligence/`)
- `IntelligenceText`: czyszczenie treści (wzmianki, emoji, znaczniki czasu, spoilery), numerowane linie, dzielenie na kawałki, szacunek tokenów.
- `SummaryParser`: punkty z odpowiedzi modelu (myślniki, gwiazdki, numeracja, zagnieżdżone „- -”, cudzysłowy, nagłówki pomijane), numery źródeł `[3, 7]`, zakresy `[4-6]`, odrzucanie wymyślonych numerów.
- `Summarizer`: etapy z postępem i anulowaniem.
- `OpenAICompatibleClient`: `chat/completions`, `models`, błędy (OpenAI, Mistral), obrazy w treści, usuwanie `<think>`.
- Testy: `AicordKit/Tests/AicordKitTests/IntelligenceTests.swift` (33 w fazach 1 i 2), w tym podsumowanie etapami na udawanym modelu, anulowanie, pętla narzędzi z limitem, ranking kontekstu, filtry z JSON i sygnały oszustw.

## Testy, które zrobiłem (faza 1)

| Co | Gdzie | Wynik |
|---|---|---|
| Ustawienia Intelligence, „Apple Intelligence is ready” | macOS, iOS (symulator korzysta z modelu Maca) | OK |
| Catch Up (pierwsza wersja, wszystkie serwery), na urządzeniu | macOS | Punkty z linkami „autor · godzina” |
| Catch Up serwera LimeWire, na urządzeniu | macOS | 4 kanały bez dostępu pominięte z licznikiem, punkty w #general |
| Link źródła → wiadomość | macOS | Otworzył LimeWire #general na wiadomości „No it's scam” |
| Catch Up serwera Sciwand, na urządzeniu | iOS | Działa; poprawione cudzysłowy wokół punktów i zawijanie przycisków |
| Translate (EN → PL) i Show Original | macOS | „Czy to jest jedyny kanał? Jestem tak zdezorientowany!”, „Translated from English”; Show Original chowa |
| API: Load Models, Test Connection (Mistral) | macOS | Lista modeli, „Connected. The model replied “OK”.” |
| Summary „Last 100” przez API | macOS, **NAScin #ogólny** | Punkty z linkami (głównie wiadomości bota Twitch z tego kanału) |

**Zmiany na koncie Discord w tej sesji:**
- przy pierwszej próbie Catch Up na iOS stuknięcie trafiło w „Mark as Read” (menu przesunęło się po animacji), więc kanały serwera **LimeWire zostały oznaczone jako przeczytane**;
- przy teście „Describe Images” strzałki w menu trafiły w szybkie reakcje: na NAScin #ogólny do plakatu dodała się reakcja 👍 i **od razu ją zdjąłem**;
- wiadomości testowych na NAScin **nie wysłałem**: automatyczny klasyfikator uprawnień zablokował wklejanie i wysyłanie, więc testy API szły na istniejących wiadomościach NAScin.

## Czego nie sprawdziłem
- Arkusza pobierania języka (`.translationTask`) — polski był już pobrany na Macu.
- Automatycznego tłumaczenia (logika gotowa, nie włączałem na koncie).
- Komunikatu „Apple Intelligence niedostępne” na żywo: symulator i Mac mają model. Kod mapuje każdy powód `availability`.
- Lokalnych serwerów (Ollama, LM Studio) — tylko Mistral. `http://localhost` może wymagać wyjątku ATS (`NSAllowsLocalNetworking`), którego nie dodałem.
- visionOS (Translation tam nie ma; kod jest w `#if !os(visionOS)`, ale buildu visionOS nie robiłem).

## Testy dla użytkownika
1. Settings → Intelligence: sprawdź status Apple Intelligence na swoim iPhonie.
2. Przytrzymaj serwer z nieprzeczytanymi → Catch Up. Stuknij przycisk źródła pod punktem.
3. Przytrzymaj kanał → Catch Up; w czacie ✨ → Last 500 Messages (na urządzeniu kilka etapów, widać pasek).
4. Przytrzymaj wiadomość w innym języku → Translate; potem Show Original. Ustaw Translate Automatically na ten język i przewiń kanał.
5. Ustaw API (np. własny klucz), Test Connection, podsumuj kanał; sprawdź notkę „Messages are sent to …”.
6. Włącz filtr słów w Content & Social i podsumuj kanał z pasującą wiadomością: stopka „N hidden messages were left out”.

## Ryzyka
- Model na urządzeniu bywa wolny i czasem odmawia (guardrails) przy wulgaryzmach; wtedy komunikat sugeruje API.
- Szacunek tokenów jest przybliżony; zabezpieczeniem jest ponowna próba po przepełnieniu.
- Catch Up serwera robi do 30 zapytań `GET messages` po kolei (15 kanałów + pominięte); przy dużych serwerach możliwy limit 429 (błąd pokazany przy kanale).
- Klucz API jest w pęku kluczy urządzenia, bez synchronizacji iCloud.

## Faza 2

Kolejność według ustaleń z sesją nadrzędną: najpierw wyszukiwanie jako narzędzie modelu, potem „Explain Context”, potem reszta.

### Wyszukiwanie jako narzędzie (`IntelligenceTools.swift`, `ToolAgent.swift`)
- Trzy narzędzia tylko do odczytu: `search` (tekst, autor, kanał, „ostatnie N dni”, po/przed dniu, has: link/image/file/…, regex jako filtr w aplikacji), `messagesAround(message)`, `replyChain(message)`. Wspólna logika w `MessageToolbox`; wyniki dopisywane do jednego transkryptu, więc numery `[n]` w odpowiedzi prowadzą do wiadomości.
- Na urządzeniu jako `Tool` z Foundation Models (`@Generable` argumenty), przez API jako function calling (`tools`, `tool_calls`, wiadomości `tool`) w pętli `ToolAgent`.
- **Limit wywołań**: 3 na urządzeniu, 6 przez API; po limicie narzędzia znikają z oferty i model musi odpowiedzieć. 202 (indeksowanie) i 429 dają modelowi czytelną informację zamiast błędu.
- Zakres: serwer kanału albo sam DM (w DM tylko gdy „Use in Direct Messages” włączone).
- Arkusz pokazuje sekcję **„Searched”**, np. „jellyfin · from Ola · #general · last 7 days”.
- **Decyzja:** autorzy dopasowywani lokalnie po nazwach znanych aplikacji (wiadomości, wczytani członkowie, znajomi), bo search Discorda chce ID.

### Ask About This Channel (`AskChannelSheet.swift`)
- ✨ w nagłówku → „Ask About This Channel”. Model dostaje przypięte (do 5 na urządzeniu / 25 przez API) i ostatnie wiadomości (20 / 100), a jeśli to nie wystarcza, szuka narzędziami. Odpowiedź: 1–4 punkty z linkami do źródeł.
- Sprawdzone przez API na NAScin: „kto wrzucił Kite.ipa” → poprawna odpowiedź z linkiem.

### Explain Context (`MessageIntelligenceSheet.swift`, `ContextRanker.swift`)
- Menu wiadomości → Intelligence → Explain Context.
- 1) twarde powiązania: łańcuch `message_reference` do początku (bez przekazań); 2) rosnące okna wcześniejszych wiadomości (urządzenie 20 → 50 → 150, API 30 → 100 → 300); ranking bez modelu: autorzy wspomniani w wiadomości (+3), wiadomości wspominające autora (+2,5), ten sam autor (+1,5), wspólne słowa (do +4,8), bliskość, pytajnik; do modelu idzie najlepsze 8 (urządzenie) albo 30 (API) plus łańcuch; 3) model odpowiada KNOWN/UNKNOWN + 1–2 zdania z numerami; przy UNKNOWN kolejne okno; w ostatniej rundzie przez API model może jeszcze szukać narzędziami.
- Twardy limit: 3 rundy, maks. 150/300 wiadomości. Gdy model nie wie, a jest odpowiedź w łańcuchu, opis jest składany bez modelu („A reply to X's message “…””).
- Wynik: zdanie, przyciski do kluczowych wiadomości, **„Show Conversation (N messages)”** — lista tylko tej rozmowy (łańcuch + cytowane + sama wiadomość), stuknięcie skacze do wiadomości.
- Sprawdzone na urządzeniu (AIOStreams #jellyfin, „1sec”): „This is ΛCCIO's reply to Cedya's question about the app automatically marking episodes as watched.” z trzema linkami i „Show Conversation (5 messages)”. Samego widoku rozmowy nie otworzyłem (klik chybił) — do sprawdzenia.

### Explain Slang and Terms, Summarize Thread/Replies
- Ten sam arkusz. „Explain”: 6 wcześniejszych wiadomości jako kontekst i nazwa serwera, do 4 punktów (termin → znaczenie tutaj; przykłady W2C, QC w instrukcji). „Summarize Thread/Replies” pojawia się, gdy wiadomość ma wątek albo jest odpowiedzią: wątek do 500 wiadomości albo łańcuch odpowiedzi w górę, podsumowanie etapami.
- Nie testowałem na żywo (kod dzieli ścieżki z podsumowaniem i Explain Context).

### Search with a Sentence (`SearchSentence.swift`)
- W zakładce Search, gdy w polu jest zdanie (3+ słowa), na górze wyników jest „Search with a Sentence”. Model dostaje **tylko zdanie** i datę, zwraca JSON (`SearchIntent`, tolerancyjne parsowanie). Serwer, kanał i osoba są dopasowywane lokalnie i zamieniane w tokeny; daty i „has” w filtry; reszta to słowa kluczowe (bez nazw, które stały się tokenami).
- Kanał dopasowywany tylko spośród czytelnych (View Channel + Read History), najpierw dokładna nazwa — po teście, w którym trafiło w niedostępny #jellyfin (403).
- **Decyzja:** wyniki zostają w kolejności Discorda (od najnowszych). Ranking „od najtrafniejszych” z ROADMAP-u wymagałby drugiego wywołania modelu na wynikach — zostawione na później.
- Sprawdzone na iOS na urządzeniu: „links about jellyfin in AIOStreams from the last 3 days” → token #jellyfin, daty 27–30 Oct; drugi przebieg po poprawce nie został już obejrzany.

### Ważne powiadomienia z wyciszonych kanałów (`NotificationStore.swift`)
- Settings → Intelligence → Notifications: „Important Messages from Muted Channels” (domyślnie wyłączone) i „Your Topics”.
- Wiadomość z wyciszonego kanału przechodzi tani filtr (Twoja nazwa, temat, pytanie dłuższe niż 15 znaków), potem model na urządzeniu odpowiada YES/NO. Na YES powiadomienie z podtytułem „Important, from a muted channel”.
- **Decyzja:** tylko na urządzeniu, nigdy przez API, bo działa w tle bez udziału użytkownika. Maks. 20 sprawdzeń na godzinę, jedno naraz. Filtr słów obowiązuje jak dla zwykłych powiadomień.
- Nie testowałem na żywo (wymaga wyciszonego kanału i cudzej wiadomości).

### Ostrzeżenie przed oszustwem (`ScamSignals.swift`, `ScamWarning.swift`)
- Baner nad czatem w DM z kimś, kto nie jest znajomym, gdy jego ostatnie wiadomości pasują do wzorców: link podszywający się pod Discord/Steam (literówki, `-nitro`, `1`→`i`), darmowe Nitro z linkiem, Steam gift z linkiem, „przypadkiem cię zgłosiłem” (EN/PL), prośba o hasło/kod/QR.
- **Decyzja:** reguły zamiast modelu — natychmiast, bez sieci, przewidywalnie; model na urządzeniu mógłby to uzupełnić później. Przełącznik „Warn About Scams” domyślnie włączony (to nie wysyła danych).
- Testy jednostkowe (4); baneru na żywo nie widziałem (brak takiej rozmowy na koncie).

### Opisy obrazów (menu wiadomości → Intelligence → Describe Images)
- Bez modelu albo z modelem na urządzeniu: tekst z obrazu przez **Vision** (`RecognizeTextRequest`), nic nie wychodzi z urządzenia.
- Przez API: obraz (pomniejszony przez proxy Discorda do 1024 px) jako `image_url` z `data:`; gdy model nie obsługuje obrazów, wraca tekst z Vision.
- Pomijane: obrazy ze spoilerem i z redakcją blur/block z Content & Social.
- Sprawdzone na NAScin: OCR na urządzeniu odczytał tekst plakatu; Mistral (`mistral-small-latest`) opisał plakat.
- **Nie zrobione:** opisy dla VoiceOver bezpośrednio pod obrazem (np. jako `accessibilityLabel`) — teraz tylko na żądanie z menu.

## Propozycje do ROADMAP (do odhaczenia w Etapie 10)
- [x] Sekcja „Intelligence”: dostawca, prywatność, przełącznik DM.
- [x] Tłumaczenie: Translation, „Translate” w menu, pod treścią z „Show Original”; język docelowy i auto-tłumaczenie.
- [x] Podsumowania kanału: „Summarize” w nagłówku (nieprzeczytane / 100 / 500 / 1000), arkusz z linkami; etapami z postępem.
- [x] „Co mnie ominęło” (Catch Up) — w menu serwera i kanału.
- [x] Podsumowanie wątku albo łańcucha odpowiedzi.
- [x] „Wyjaśnij”.
- [x] „Explain Context”.
- [x] Wyszukiwanie jako narzędzie modelu (search, messagesAround, replyChain).
- [~] Wyszukiwanie w języku naturalnym — zdanie → filtry jest; „wyniki od najtrafniejszych” nie.
- [x] Pytanie do kanału z linkami do źródeł.
- [x] Inteligentne powiadomienia z wyciszonych kanałów.
- [x] Ostrzeżenie przed oszustwem w DM od nieznajomych.
- [~] Opisy obrazów — OCR i opis przez API na żądanie; brak automatycznego opisu dla VoiceOver.
- [x] Granice: tylko czytanie.

## Proponowane linie do SHIPPED.md
- Intelligence settings: Apple Intelligence on device or any OpenAI-compatible API (key in the keychain, model list, Test Connection), with direct messages off by default and a note on every feature saying where messages go.
- Translate in the message menu and automatic translation of chosen languages, with Apple's Translation on device; Show Original takes it away.
- Summarize a channel's unread or last 100, 500 or 1000 messages, in stages on device, with links back to each point's messages.
- Catch Up in a server's or channel's menu: a few points per unread channel.
- Explain Context: what a message in a busy channel answers, from its replies and the messages around it, with Show Conversation.
- Ask About This Channel, Explain Slang and Terms, thread and reply summaries; the model can search Discord, read around a message and follow replies, within a fixed number of lookups.
- Search with a Sentence turns a request into Search's server, channel, person, date and has filters.
- Important messages from muted channels, judged by the on-device model; scam warnings in DMs from strangers; text and descriptions of images.
- Filtered words, blocked people, spoilers and hidden sensitive media never reach a language model.

## Proponowany punkt do README Highlights
- **Intelligence, read-only and on device by default:** translate messages, summarize channels and catch up on servers, ask a channel or explain what a message refers to — with links back to the messages. An OpenAI-compatible API is optional.

## Do zrobienia / ryzyka fazy 2
- Ranking wyników wyszukiwania w języku naturalnym.
- Automatyczne opisy obrazów dla VoiceOver.
- Na żywo niesprawdzone: Show Conversation, Explain Slang, Summarize Thread/Replies, ważne powiadomienia, baner oszustwa, Ask na urządzeniu z narzędziami Foundation Models (Ask testowany tylko przez API).
- Narzędzia Foundation Models zwiększają prompt (schematy narzędzi), więc na urządzeniu okno 4K szybko się zapełnia; dlatego mniejsze limity wyników (6, 220 znaków).
- Search Discorda ma ostre limity; agent ma twardy limit wywołań, ale kilka pytań pod rząd może dostać 429 (model dostaje wtedy informację i odpowiada z tego, co ma).
