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
   - [ ] Language: na koniec, po pozostałych poprawkach. Voice & Video powstaje razem z Etapem 9 (wybór urządzeń, push-to-talk, wyciszenie).
   - Nie robimy: powiadomień push na iOS, gdy Aicord jest zamknięty. Wymagałyby własnego serwera trzymającego token konta i połączenie z gatewayem; zostają lokalne powiadomienia z działającej aplikacji.
8. **Poprawki interfejsu (po Ustawieniach):**
   - Nie robimy: Purge (masowe usuwanie wiadomości z czatu). API Discorda pozwala usunąć tylko własne wiadomości w DM, a cudze na serwerze tylko z Manage Messages; masowe usuwanie z konta użytkownika to automatyzacja, za którą Discord blokuje konta (ostrzega przed tym nawet Undiscord).
   - [ ] Przeklikać na prawdziwych danych akcje, których sesja nie robiła: Accept / Ignore / Reject próśb o wiadomość, Not Spam / Delete w Spamie, zaproszenia do znajomych, Forward do DM, kilku celów naraz i z Maca. Lista kroków: `docs/MESSAGES_NOTES.md`. Do tego z zaproszeń: prawdziwe Add Friend (z listy i z profilu) i rozszerzenie Safari na macOS. Kroki: `docs/INVITES_NOTES.md`. (Join na nowym serwerze przez Safari na iPhonie sprawdzony 30.10.2026.)
   - [ ] Natywne listy: sprawdzić na iPadzie i przewijanie dużej listy członków (`docs/LISTS_NOTES.md`).
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
2. **Dokończenia:**
   - [ ] Okno 4 tys. tokenów na urządzeniu szybko się zapełnia przy narzędziach (wyniki przycięte do 6 po 220 znaków): sprawdzić jakość odpowiedzi i ewentualnie mniejsze schematy narzędzi.
3. **Wyszukiwanie po sensie:**
   - [ ] „Index Channel” dla wybranych kanałów: lokalny indeks wektorowy ostatnich N wiadomości (pobieranie historii po 100 na zapytanie, z limitami, więc z paskiem postępu), aktualizowany o nowe wiadomości, z rozmiarem na dysku i „Delete Index”. Foundation Models nie daje wektorów; opcjonalnie mały wielojęzyczny model embeddingowy w Core ML (lepsza jakość, aplikacja większa o kilkadziesiąt–sto MB).
4. **Granice:**
   - Nie robimy: pomocy w pisaniu (poprawianie, ton, tłumaczenie szkicu), bo daje ją już system (Writing Tools w iOS i macOS).

---

### 🔜 Etap 11: Aicord dla macOS
Aicord na Macu to już natywna aplikacja (jeden wieloplatformowy target SwiftUI, nie Mac Catalyst), ale dzieli szkielet `LargeBaseplate` z iPadem i przez to wygląda jak aplikacja na iPada. Etap 7 i zmiana nazw (5.4) są już zrobione, więc można zaczynać. Listy kanałów i członków są już systemowe (styl `.sidebar` na Macu), więc szkielet może z nich korzystać.
1. **Interfejs Maca:**
   - [ ] Własny szkielet `MacBaseplate` zamiast wspólnego z iPadem: pasek boczny serwerów i kanałów w stylu systemowym, paski narzędzi, inspektor członków.
   - [ ] Menu aplikacji, skróty, wiele okien (kanał w osobnym oknie), Ustawienia jako systemowe okno `Settings`.
2. **Serwer MCP (połączenie Claude z Discordem):**
   - [ ] Mały pomocniczy program (target command-line) rozmawiający przez stdio i przekazujący zapytania do działającej aplikacji Aicord; aplikacja główna zostaje jedna.
   - [ ] Domyślnie tylko odczyt (kanały, wiadomości, wyszukiwanie, podsumowania). Wysyłanie najwyżej z potwierdzeniem każdej akcji w aplikacji: działanie przez token użytkownika to automatyzacja konta, której Discord zabrania (self-bot), więc ryzyko blokady trzeba ograniczyć.

---

### 🔜 Etap 12: Wydania — macOS i iOS w GitHub Releases
Na końcu, gdy aplikacja jest stabilna. Wydanie budowane przez GitHub Actions z tagu `v*` (dziś jest tylko `build_pr.yml`, bez podpisu).
1. **macOS: podpisana aplikacja z aktualizacjami:**
   - [ ] Podpis Developer ID i notaryzacja (wymaga płatnego konta Apple Developer). Certyfikat i klucz API App Store Connect jako sekrety repozytorium, `.app` w `.zip` albo `.dmg` w Releases.
   - [ ] Powiadomienie o aktualizacji. Do wyboru: Sparkle 2 z własnym appcastem i kluczem EdDSA (w Etapie 1 usunięty razem z kanałem llsc12; pobiera i instaluje sam) albo lekkie sprawdzanie najnowszego wydania przez API GitHuba z linkiem do pobrania. Wyłącznik w Settings → Advanced.
2. **iOS: niepodpisana `.ipa` i źródło AltStore:**
   - [ ] Build bez podpisu (`CODE_SIGNING_ALLOWED=NO`), `Payload/Aicord.app` spakowane do `.ipa` w Releases.
   - [ ] Repozytorium AltStore (działa też w SideStore): plik źródła JSON (nazwa, ikona, opis, wersje z linkami do `.ipa`, uprawnienia) generowany przez workflow przy każdym wydaniu i publikowany np. na GitHub Pages.
   - [ ] Sprawdzić uprawnienia i rozszerzenia pod darmowe konto: AltStore podpisuje kontem użytkownika, a darmowe konto ma limit 3 App ID, więc każde rozszerzenie (np. Safari z Etapu 8) zjada jedno miejsce. Push i inne uprawnienia płatnego konta nie zadziałają.
3. **Opis wydań:**
   - [ ] Notatki do wydania z `SHIPPED.md` (Etap 6.4), link do źródła AltStore i instrukcja instalacji w README.
