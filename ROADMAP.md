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
   - [ ] Dalsze odchudzanie `DiscordModels` (4,45 MB): największe są teraz `CodingKeys` (~0,9 MB) oraz `init(from:)`/`encode(to:)`; `SwiftProtobuf` to 1,15 MB.
   - [ ] `Textual/Tests` nie ma targetu testów w `Package.swift`, więc testy snapshotowe nigdy się nie uruchamiają: dodać target z zależnością od swift-snapshot-testing albo usunąć katalog.

---

### ⏳ Etap 8: Odświeżenie UI
4. **Ustawienia:**
   - [ ] Language: na koniec, po pozostałych poprawkach. Voice & Video powstaje razem z Etapem 9 (wybór urządzeń, push-to-talk, wyciszenie).
   - Nie robimy: powiadomień push na iOS, gdy Aicord jest zamknięty. Wymagałyby własnego serwera trzymającego token konta i połączenie z gatewayem; zostają lokalne powiadomienia z działającej aplikacji.
8. **Poprawki interfejsu (po Ustawieniach):**
   - Nie robimy: Purge (masowe usuwanie wiadomości z czatu). API Discorda pozwala usunąć tylko własne wiadomości w DM, a cudze na serwerze tylko z Manage Messages; masowe usuwanie z konta użytkownika to automatyzacja, za którą Discord blokuje konta (ostrzega przed tym nawet Undiscord).
   - [ ] Przeklikać na prawdziwych danych akcje, których sesja nie robiła: Accept / Ignore / Reject próśb o wiadomość, Not Spam / Delete w Spamie, zaproszenia do znajomych, Forward do DM, kilku celów naraz i z Maca. Lista kroków: `docs/MESSAGES_NOTES.md`.
   - [ ] Kontener kanałów na Home w ciemnym motywie: lewy górny róg zaokrąglony (25 pt), prawy ucięty krawędzią ekranu, więc wygląda niespójnie. Oba górne rogi zaokrąglone, prawy dopasowany do zaokrąglenia ekranu (albo żaden).
   - [ ] Widok serwerów i kanałów od nowa, bardziej natywnie: kanały jako `List` w stylu `.sidebar` z systemowo zwijanymi sekcjami (`Section(isExpanded:)`), zaznaczeniem, przesunięciami i menu, pasek serwerów jako wąska kolumna, bez własnego kontenera, tła i masek. Dynamic Type, VoiceOver, ciemny motyw i Liquid Glass bez ręcznych poprawek. W tej samej przeróbce lista członków (`Member Sidebar`, dziś `ScrollView` z `LazyVStack`) jako `List` z sekcjami ról. Czat, popouty profilu, logowanie i szybki przełącznik zostają własne. Razem z Etapem 11, bo Mac też odchodzi od wspólnego szkieletu; po tej przeróbce punkt o rogach wyżej znika sam.
   - [ ] Add Friend: wysyłanie zaproszenia do znajomych po nazwie użytkownika w Messages → Friends oraz z profilu osoby (`sendFriendRequest` już jest w AicordKit).
   - [ ] Invite People w menu serwera: link zaproszenia z czasem ważności i limitem użyć, do skopiowania i udostępnienia (`createChannelInvite`).
   - [ ] Join: przycisk na karcie zaproszenia w czacie i po otwarciu linku `discord.gg/…`, z podglądem serwera przed dołączeniem (`resolveInvite`, `acceptInvite`). Potrzebne też rozszerzeniu Safari poniżej.
   - [ ] Rozszerzenie Safari: linki zaproszeń `discord.gg/…` i `discord.com/invite/…` otwierane w Aicord przez własny schemat URL (Universal Links dla discord.com należą do Discorda). Osobny target, włączany przez użytkownika w ustawieniach Safari.

---

### 🧪 Etap 9: Voice — kanały głosowe i rozmowy w DM
Szczegóły portu, decyzje i instrukcja testu: `docs/VOICE_NOTES.md`.
6. **Weryfikacja:**
   - [ ] Ręczny test na koncie (zrobione: dołączenie do pustego kanału serwera i wyjście, z DAVE v1, na symulatorze iOS; zostaje test z drugą osobą, patrz `docs/VOICE_NOTES.md`): dźwięk w obie strony z DAVE w DM, w rozmowie grupowej i na kanale serwera; dołączanie i wychodzenie uczestników; wznowienie po zerwaniu sieci.
7. **Później:**
   - [ ] Wideo i udostępnianie ekranu. Serein ma do tego ścieżki na macOS (ScreenCaptureKit, VideoToolbox).

---

### 🔜 Etap 10: Intelligence — tłumaczenie i podsumowania
Po Etapie 7 (odchudzenie biblioteki) i po scaleniu zestawu Messages (Forward zmienia to samo menu wiadomości). Działa na iOS i macOS, na obecnym targecie.
1. **Sekcja ustawień „Intelligence” (Aicord Settings):**
   - [ ] Dostawca: na urządzeniu (Foundation Models / Apple Intelligence, z kontrolą dostępności urządzenia i regionu) albo API zgodne z OpenAI (adres, klucz w pęku kluczy, model, „Test Connection”). Pasuje też lokalny serwer (Ollama, LM Studio).
   - [ ] Prywatność: domyślnie tylko na urządzeniu; zewnętrzne API wyłączone, dopóki ktoś go nie skonfiguruje; przy każdej funkcji informacja, dokąd idą dane; osobny przełącznik dla DM, domyślnie wyłączony.
2. **Tłumaczenie:**
   - [ ] Framework Translation zamiast modelu językowego (na urządzeniu, bez klucza). „Translate” w menu wiadomości, tłumaczenie pod treścią z możliwością cofnięcia.
   - [ ] Język docelowy i automatyczne tłumaczenie wybranych języków.
3. **Podsumowania kanału:**
   - [ ] „Summarize” w nagłówku kanału: nieprzeczytane albo ostatnie 100 / 500 / 1000 wiadomości. Wynik w arkuszu, punkty z linkami do wiadomości.
   - [ ] Na urządzeniu okno kontekstu to ok. 4 tys. tokenów: podsumowanie etapami (kawałki, potem podsumowanie podsumowań), z postępem. Przez API całość jednym zapytaniem, gdy się mieści.
4. **Czytanie i nadrabianie:**
   - [ ] „Co mnie ominęło”: wszystkie nieprzeczytane kanały naraz jako jedna lista (serwer → kanał → 2–3 punkty).
   - [ ] Podsumowanie wątku albo łańcucha odpowiedzi od wybranej wiadomości w górę.
   - [ ] „Wyjaśnij”: slang, skróty i żargon serwera (np. W2C, QC) z kontekstem kilku wcześniejszych wiadomości.
5. **Wyszukiwanie:**
   - [ ] Wyszukiwanie w języku naturalnym w Search: zdanie („kto polecał agenta do wysyłki w zeszłym tygodniu”) zamienione na filtry (autor, kanał, daty, „zawiera link”), wyniki ułożone od najtrafniejszych.
   - [ ] Pytanie do kanału („jaki jest regulamin aukcji?”): odpowiedź z linkami do wiadomości źródłowych, na przypiętych i ostatnich wiadomościach.
6. **Porządek i bezpieczeństwo:**
   - [ ] Inteligentne powiadomienia: lokalny model ocenia, czy wiadomość z wyciszonego kanału jest dla Ciebie ważna (pytanie do Ciebie, Twoje tematy), i wtedy powiadamia mimo wyciszenia. Rozszerza sekcję Notifications.
   - [ ] Ostrzeżenie przed oszustwem w DM od nieznajomych: fałszywe Nitro, „przypadkowe zgłoszenie konta”, linki phishingowe. Na urządzeniu, uzupełnia filtr spamu z Content & Social.
   - [ ] Opisy obrazów bez tekstu alternatywnego (także dla VoiceOver): tekst z obrazka przez Vision (OCR) na urządzeniu, pełny opis przez API, jeśli model widzi obrazy (Foundation Models ich nie obsługuje).
7. **Granice:**
   - [ ] Tylko czytanie: Intelligence niczego nie wysyła do Discorda (bez automatycznych odpowiedzi), więc nie jest automatyzacją konta.
   - Nie robimy: pomocy w pisaniu (poprawianie, ton, tłumaczenie szkicu), bo daje ją już system (Writing Tools w iOS i macOS).

---

### 🔜 Etap 11: Aicord dla macOS
Aicord na Macu to już natywna aplikacja (jeden wieloplatformowy target SwiftUI, nie Mac Catalyst), ale dzieli szkielet `LargeBaseplate` z iPadem i przez to wygląda jak aplikacja na iPada. Po Etapie 7 i zmianie nazw targetów (Etap 5.4), żeby przebudowywać targety i `pbxproj` tylko raz.
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
