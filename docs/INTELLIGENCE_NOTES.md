# Intelligence (Etap 10): notatki

Gałąź `claude/intelligence-5f310a`. Praca autonomiczna, commity podpisane tylko użytkownikiem.

## Stan

- **Faza 1: zrobiona i sprawdzona** na macOS (prawdziwe konto) i iOS (symulator iPhone 18 Pro).
- **Faza 2:** opis w sekcji „Faza 2” niżej.
- Buildy iOS (symulator) i macOS przechodzą. `swift test` w `AicordKit`: 129 testów (110 + 19 nowych), 0 błędów.

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
- Testy: `AicordKit/Tests/AicordKitTests/IntelligenceTests.swift` (19), w tym podsumowanie etapami na udawanym modelu i anulowanie.

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

**Uwaga:** przy pierwszej próbie Catch Up na iOS stuknięcie trafiło w „Mark as Read” (menu przesunęło się po animacji), więc kanały serwera **LimeWire zostały oznaczone jako przeczytane** na koncie. To jedyna zmiana na koncie Discord w tej sesji (poza wiadomościami testowymi na NAScin, jeśli są opisane niżej).

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
