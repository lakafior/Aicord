# Aicord — Roadmap

Co jeszcze przed nami. To, co już zrobione, jest w [SHIPPED.md](SHIPPED.md): lista zmian i pełna historia etapów, z tą samą numeracją etapów i punktów co tutaj. Notatki z dużych prac (decyzje, testy) leżą w [`docs/`](docs/).

Kierunek: czysty **Swift 6**, **iOS 26 i macOS 26**, natywne **SwiftUI** z **Liquid Glass**, prawie wyłącznie frameworki Apple.

---

### 🔜 Etap 6: Tożsamość Aicord, poprawki i dokumentacja
4. **Porządek w dokumentacji:**
   - [ ] Zrzuty ekranu do README z iPhone'a i Maca, zrobione na NAScin (bez cudzych wiadomości i nicków).

---

### 🔜 Etap 7: Własne biblioteki zamiast forków (`AicordKit`, `Textual`)
Biblioteka to już `AicordKit` (zrobione: patrz SHIPPED i `docs/SLIM_NOTES.md`). Zostały propozycje z tamtej pracy:
4. **Dalej:**
   - [ ] Dalsze odchudzanie `DiscordModels` (4,15 MB po nocy 30/31.10): `CodingKeys` to nadal ~0,9 MB, prawie w całości metadane (5 konformancji na każdy z 385 enumów). Zejść z tego może tylko własne dekodowanie ze wspólnym typem klucza (makro generujące `init(from:)`), co jest dużą i ryzykowną zmianą; `SwiftProtobuf` to 1,15 MB. Szczegóły i pomiary: `docs/OVERNIGHT.md`.

---

### ⏳ Etap 8: Odświeżenie UI
4. **Ustawienia:**
   - [ ] Język: zsynchronizować katalog w Xcode (build w IDE dopisze napisy dodane od Etapu 8, których nie ma w `Localizable.xcstrings`) i przetłumaczyć nowe wpisy; liczby po polsku (1 / 2–4 / 5+) przez warianty liczby mnogiej zamiast `^[…](inflect:)`; przejrzeć tłumaczenie w aplikacji. Voice & Video powstaje razem z Etapem 9 (wybór urządzeń, push-to-talk, wyciszenie).
   - Nie robimy: powiadomień push na iOS, gdy Aicord jest zamknięty. Wymagałyby własnego serwera trzymającego token konta i połączenie z gatewayem; zostają lokalne powiadomienia z działającej aplikacji.
8. **Poprawki interfejsu (po Ustawieniach):**
   - Nie robimy: Purge (masowe usuwanie wiadomości z czatu). API Discorda pozwala usunąć tylko własne wiadomości w DM, a cudze na serwerze tylko z Manage Messages; masowe usuwanie z konta użytkownika to automatyzacja, za którą Discord blokuje konta (ostrzega przed tym nawet Undiscord).
   - [ ] Przeklikać na prawdziwych danych akcje, których sesja nie robiła: Accept / Ignore / Reject próśb o wiadomość, Not Spam / Delete w Spamie, zaproszenia do znajomych, Forward do DM, kilku celów naraz i z Maca. Lista kroków: `docs/MESSAGES_NOTES.md`. Do tego z zaproszeń: prawdziwe Add Friend (z listy i z profilu) i rozszerzenie Safari na macOS. Kroki: `docs/INVITES_NOTES.md`. (Join na nowym serwerze przez Safari na iPhonie sprawdzony 30.10.2026.)
   - [ ] Natywne listy: sprawdzić na iPadzie i przewijanie dużej listy członków (`docs/LISTS_NOTES.md`).
   - [ ] Komponenty i forum, dalszy ciąg (`docs/COMPONENTS_V2.md`): przyciski i menu botów (v1 i v2) działają tylko do odczytu, bo klient nie wysyła interakcji (`POST /interactions`); w forum brak tworzenia posta, wyszukiwania po nazwie i siatki dla kanałów media; post otwarty w osobnym oknie Maca nie przełącza okna.
   - [ ] Na Macu po poprawce z nocy 30/31.10: kliknięcie linku (także zaproszenia) w treści wiadomości, Esc po przewinięciu czatu, Safari → Extensions z ekranu instrukcji (`docs/OVERNIGHT.md`).

---

### 🧪 Etap 9: Voice — kanały głosowe i rozmowy w DM
Szczegóły portu, decyzje i instrukcja testu: `docs/VOICE_NOTES.md`.
6. **Weryfikacja:**
   - [ ] Ręczny test na koncie (zrobione: dołączenie do pustego kanału serwera i wyjście, z DAVE v1, na symulatorze iOS; zostaje test z drugą osobą, patrz `docs/VOICE_NOTES.md`): dźwięk w obie strony z DAVE w DM, w rozmowie grupowej i na kanale serwera; dołączanie i wychodzenie uczestników; wznowienie po zerwaniu sieci.
7. **Później:**
   - [ ] Wideo i udostępnianie ekranu. Serein ma do tego ścieżki na macOS (ScreenCaptureKit, VideoToolbox).

---

### 🧪 Etap 10: Intelligence — tłumaczenie i podsumowania
Zrobione (szczegóły w SHIPPED i `docs/INTELLIGENCE_NOTES.md`): ustawienia, tłumaczenie, podsumowania, Catch Up, Explain Context, wyszukiwarka jako narzędzie modelu, pytanie do kanału, Wyjaśnij, podsumowanie wątku, Search with a Sentence, ważne powiadomienia, ostrzeżenie przed oszustwem, opisy obrazów. Zostało:
1. **Weryfikacja:**
   - [ ] Na urządzeniu: opisy obrazów z VoiceOverem (etykieta z tekstem z Vision, opcjonalnie z API), Show Conversation, Explain Slang, podsumowanie wątku i odpowiedzi, ważne powiadomienia z wyciszonych kanałów, baner oszustwa, Ask na urządzeniu z narzędziami Foundation Models (sprawdzone tylko przez API), arkusz pobierania języka i automatyczne tłumaczenie. Lista kroków: `docs/INTELLIGENCE_NOTES.md`.
   - [ ] Komunikat „Apple Intelligence niedostępne” na urządzeniu bez modelu.
   - [ ] Show Thread i Explain Context na długim wątku (ponad 50 odpowiedzi, rodzice spoza wczytanej historii) i z modelem przez API; menu pod nazwą kanału i podmenu Intelligence przeklikać na Macu (sprawdzone tylko w symulatorze iOS na krótkim wątku, `docs/THREAD_AI.md`).
2. **Dokończenia:**
3. **Wyszukiwanie po sensie:**
   - [ ] Index Channel: aktualizacja indeksu o nowe wiadomości z gatewaya w tle (dziś przycisk „Add New Messages”) i, opcjonalnie, mały wielojęzyczny model embeddingowy w Core ML zamiast średniej z `NLContextualEmbedding` (lepsza jakość, aplikacja większa o kilkadziesiąt–sto MB). Sprawdzić wyszukiwanie po sensie na urządzeniu z modelem (w symulatorze modelu nie ma, działało tylko po słowach).
4. **Granice:**
   - Nie robimy: pomocy w pisaniu (poprawianie, ton, tłumaczenie szkicu), bo daje ją już system (Writing Tools w iOS i macOS).

---

### 🔜 Etap 11: Aicord dla macOS
Aicord na Macu to już natywna aplikacja (jeden wieloplatformowy target SwiftUI, nie Mac Catalyst), ale dzieli szkielet `LargeBaseplate` z iPadem i przez to wygląda jak aplikacja na iPada. Etap 7 i zmiana nazw (5.4) są już zrobione, więc można zaczynać. Listy kanałów i członków są już systemowe (styl `.sidebar` na Macu), więc szkielet może z nich korzystać.
1. **Interfejs Maca:**
   - [ ] Przeklikać resztę na Macu: menu Go, kanał w osobnym oknie i okno `Settings` (kroki w `docs/OVERNIGHT.md`, punkt 5). Szkielet z danymi i menu pod prawym przyciskiem sprawdzone 31.10, więc Classic Window Layout jest usunięty.
2. **Serwer MCP (połączenie Claude z Discordem):**
   - [ ] Sprawdzić na odblokowanym Macu z prawdziwą aplikacją: włączyć Allow MCP Server, wkleić na nowo skopiowaną konfigurację (ścieżka prowadzi teraz do helpera w `.app`) do Claude Desktop, `list_servers` i `read_messages` na NAScin (kroki w `docs/OVERNIGHT.md`, punkt 5b).
   - [ ] Podsumowania jako narzędzie MCP (z modelu wybranego w Intelligence). Wysyłanie najwyżej z potwierdzeniem każdej akcji w aplikacji: działanie przez token użytkownika to automatyzacja konta, której Discord zabrania (self-bot), więc ryzyko blokady trzeba ograniczyć.

---

### 🔜 Etap 13: Brakujące funkcje Discorda
Paczka 1 zrobiona (szczegóły w SHIPPED i `docs/PACK1_NOTES.md`): wiadomości systemowe, ankiety, przypięte i przeglądarka wątków.
1. **Paczka 1, sprawdzenie:**
   - [ ] Przeklikać na Macu (sprawdzone tylko w symulatorze iOS): ankieta, tworzenie ankiety, Pinned Messages, Threads, Pin Message w menu pod prawym przyciskiem.
   - [ ] Zobaczyć na żywo typy, których nie było pod ręką: połączenie w DM (czas i nieodebrane), grupa (dodanie, usunięcie, nazwa, ikona), boost, Stage, AutoMod, zamknięta ankieta (typ 46), utworzenie wątku.
2. **Paczka 2:**
   - [ ] Onboarding serwera: pytania i wybór ról po dołączeniu (pokazuje się prawie zawsze na nowym serwerze).
   - [ ] Slash-komendy z podpowiedziami po `/`.
   - [ ] Nagrywanie wiadomości głosowych (odtwarzanie już jest).
   - [ ] Wydarzenia serwera: lista i „Zainteresowany”.
3. **Później albo wcale:**
   - [ ] Stage, soundboard, super-reakcje.
   - Nie robimy: Questy, Activities i sklep Nitro.

---

### 🔜 Etap 12: Wydania — macOS i iOS w GitHub Releases
Na końcu, gdy aplikacja jest stabilna. Przygotowane w nocy 30/31.10 (niczego nie uruchomiono na GitHubie): `release.yml` (iOS, `.ipa`, Release, źródło AltStore na Pages), `release_macos.yml` (szkic podpisu i notaryzacji) i `scripts/altstore_source.py`. Kroki i sekrety: `docs/OVERNIGHT.md`, punkt 4.
1. **macOS: podpisana aplikacja z aktualizacjami:**
   - [ ] Dodać sekrety (certyfikat Developer ID jako .p12, klucz API App Store Connect) i sprawdzić `release_macos.yml` na pierwszym tagu (wymaga płatnego konta Apple Developer).
   - [ ] Powiadomienie o aktualizacji przez API GitHuba (wybrane zamiast Sparkle, uzasadnienie w `docs/OVERNIGHT.md`): sprawdzanie najnowszego wydania przy starcie najwyżej raz dziennie, baner z linkiem do pobrania, wyłącznik w Settings → Advanced.
2. **iOS: niepodpisana `.ipa` i źródło AltStore:**
   - [ ] Włączyć GitHub Pages (Source: GitHub Actions) i wypchnąć pierwszy tag `v*`; sprawdzić, że AltStore i SideStore przyjmują źródło i instalują `.ipa`.
   - [ ] Ikona źródła w większym rozmiarze (dziś 128 px z rozszerzenia Safari) i zrzuty ekranu w źródle.
   - [ ] Sprawdzić uprawnienia i rozszerzenia pod darmowe konto: AltStore podpisuje kontem użytkownika, a darmowe konto ma limit 3 App ID, więc każde rozszerzenie (np. Safari z Etapu 8) zjada jedno miejsce. Push i inne uprawnienia płatnego konta nie zadziałają.
3. **Opis wydań:**
   - [ ] Instrukcja instalacji w README (link do źródła AltStore). Notatki do wydania są brane z najnowszej sekcji `SHIPPED.md` automatycznie.
