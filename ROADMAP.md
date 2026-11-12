# Aicord — Roadmap

Co jeszcze przed nami. To, co już zrobione, jest w [CHANGELOG.md](CHANGELOG.md): lista zmian i pełna historia etapów, z tą samą numeracją etapów i punktów co tutaj. Notatki z dawnych sesji (decyzje, testy, kroki do przeklikania) są w historii gita, linki prowadzą do nich wprost; mapa kodu jest w [ARCHITECTURE.md](ARCHITECTURE.md).

Kierunek: czysty **Swift 6**, **iOS 26 i macOS 26**, natywne **SwiftUI** z **Liquid Glass**, prawie wyłącznie frameworki Apple.

---

### 🔜 Zrzuty ekranu: dalsze ekrany w trybie demo
Galeria w README pokazuje na razie czat, serwer i DM-y. Dane demo (`Aicord/Demo/`) i ujęcia w `scripts/screenshots.sh` do dopisania:
   - [ ] Panel rozmowy głosowej z mówiącymi (stan połączenia bez prawdziwego voice).
   - [ ] Intelligence: podsumowanie kanału albo Catch Up z linkami do wiadomości (gotowa odpowiedź zamiast modelu).
   - [ ] Narzędzia moderatora: ustawienia serwera, role i uprawnienia.
   - [ ] Galeria kanału, wyszukiwarka i ustawienia.
   - [ ] Widżet i Live Activity.

---

### 🔜 Etap 7: Własne biblioteki zamiast forków (`AicordKit`, `Textual`)
Biblioteka to już `AicordKit` (zrobione: patrz CHANGELOG i [SLIM_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/SLIM_NOTES.md)). Zostały propozycje z tamtej pracy:
4. **Dalej:**
   - [ ] Dalsze odchudzanie `DiscordModels` (4,15 MB po nocy 30/31.10): `CodingKeys` to nadal ~0,9 MB, prawie w całości metadane (5 konformancji na każdy z 385 enumów). Zejść z tego może tylko własne dekodowanie ze wspólnym typem klucza (makro generujące `init(from:)`), co jest dużą i ryzykowną zmianą; `SwiftProtobuf` to 1,15 MB. Szczegóły i pomiary: [OVERNIGHT](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/OVERNIGHT.md).

---

### ⏳ Etap 8: Odświeżenie UI
4. **Ustawienia:**
   - [ ] Język: zsynchronizować katalog w Xcode (build w IDE dopisze napisy dodane od Etapu 8, których nie ma w `Localizable.xcstrings`) i przetłumaczyć nowe wpisy; liczby po polsku (1 / 2–4 / 5+) przez warianty liczby mnogiej zamiast `^[…](inflect:)`. Voice & Video powstaje razem z Etapem 9 (wybór urządzeń, push-to-talk, wyciszenie).
   - Nie robimy: powiadomień push na iOS, gdy Aicord jest zamknięty. Wymagałyby własnego serwera trzymającego token konta i połączenie z gatewayem; zostają lokalne powiadomienia z działającej aplikacji.
8. **Poprawki interfejsu (po Ustawieniach):**
   - Nie robimy: Purge (masowe usuwanie wiadomości z czatu). API Discorda pozwala usunąć tylko własne wiadomości w DM, a cudze na serwerze tylko z Manage Messages; masowe usuwanie z konta użytkownika to automatyzacja, za którą Discord blokuje konta (ostrzega przed tym nawet Undiscord).
   - [ ] Komponenty i forum, dalszy ciąg ([COMPONENTS_V2](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/COMPONENTS_V2.md), [BOT_INTERACTIONS_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/BOT_INTERACTIONS_NOTES.md)): siatka dla kanałów media; post otwarty w osobnym oknie Maca nie przełącza okna.

---

### 🔜 Etap 9: Voice — kanały głosowe i rozmowy w DM
Szczegóły portu, decyzje i instrukcja testu: [VOICE_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/VOICE_NOTES.md).
7. **Później:**
   - [ ] Wideo i udostępnianie ekranu. Serein ma do tego ścieżki na macOS (ScreenCaptureKit, VideoToolbox).

---

### 🔜 Etap 10: Intelligence — tłumaczenie i podsumowania
Zrobione (szczegóły w CHANGELOG i [INTELLIGENCE_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/INTELLIGENCE_NOTES.md)): ustawienia, tłumaczenie, podsumowania, Catch Up, Explain Context, wyszukiwarka jako narzędzie modelu, pytanie do kanału, Wyjaśnij, podsumowanie wątku, Search with a Sentence, ważne powiadomienia, ostrzeżenie przed oszustwem, opisy obrazów. Zostało:
3. **Wyszukiwanie po sensie:**
   - [ ] Index Channel: aktualizacja indeksu o nowe wiadomości z gatewaya w tle (dziś przycisk „Add New Messages”) i, opcjonalnie, mały wielojęzyczny model embeddingowy w Core ML zamiast średniej z `NLContextualEmbedding` (lepsza jakość, aplikacja większa o kilkadziesiąt–sto MB).
4. **Granice:**
   - Nie robimy: pomocy w pisaniu (poprawianie, ton, tłumaczenie szkicu), bo daje ją już system (Writing Tools w iOS i macOS).

---

### 🔜 Etap 11: Aicord dla macOS
Aicord na Macu to już natywna aplikacja (jeden wieloplatformowy target SwiftUI, nie Mac Catalyst), ale dzieli szkielet `LargeBaseplate` z iPadem i przez to wygląda jak aplikacja na iPada. Etap 7 i zmiana nazw (5.4) są już zrobione, więc można zaczynać. Listy kanałów i członków są już systemowe (styl `.sidebar` na Macu), więc szkielet może z nich korzystać.
1. **Interfejs Maca:** dopracowanie wyglądu zrobione (okno `Settings` z kartami, ustawienia serwera w osobnym oknie, przypięte, wątki i reakcje jako popovery, tytuł okna nie ginie pod arkuszem, tło czatu jak tło okna; szczegóły w `CHANGELOG.md`). Zostało:
   - [ ] Wyszukiwanie z paska narzędzi otwiera wyniki w arkuszu; lepiej pasowałyby wyniki w oknie albo w miejscu listy, jak w Mail.
   - [ ] „Media, Links and Files” i podsumowania Intelligence to nadal arkusze (o rozmiarze Maca); galeria mogłaby być osobnym oknem.
2. **Serwer MCP (połączenie Claude z Discordem):**
   - [ ] Podsumowania jako narzędzie MCP (z modelu wybranego w Intelligence). Wysyłanie najwyżej z potwierdzeniem każdej akcji w aplikacji: działanie przez token użytkownika to automatyzacja konta, której Discord zabrania (self-bot), więc ryzyko blokady trzeba ograniczyć.

---

### 🔜 Etap 13: Brakujące funkcje Discorda
Paczki 1 i 2 zrobione (szczegóły w CHANGELOG, [PACK1_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/PACK1_NOTES.md) i [PACK2_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/PACK2_NOTES.md)): wiadomości systemowe, ankiety, przypięte, przeglądarka wątków, onboarding i reguły serwera, slash-komendy, nagrywanie głosówek, wydarzenia.
3. **Później albo wcale:**
   - [ ] Soundboard, super-reakcje.
   - [ ] Modale botów: pola wyboru osób, ról i kanałów oraz upload pliku (typ 19) w modalu; dziś pokazujemy tylko tekst, menu tekstowe i napisy. Stan wypełnionego modala ginie po przejściu do innego kanału.
   - [ ] Activities, eksperyment (dziś jest tylko karta „Open in Discord”): Activity to strona `https://<application_id>.discordsays.com` w WebView, która rozmawia z klientem przez Embedded App SDK (`postMessage`, ramki RPC). Plan:
     - najpierw zmierzyć, ilu komend SDK naprawdę potrzebują popularne aktywności (np. Wordle, Gartic): zalogować ruch `postMessage` z jednej sesji;
     - minimalny most RPC: handshake (`frame_id`, `platform`), `AUTHORIZE` (kod OAuth z `POST /oauth2/authorize` dla `client_id` aktywności), `AUTHENTICATE` (token od serwera aktywności), `GET_CHANNEL`, uczestnicy (`ACTIVITY_INSTANCE_PARTICIPANTS_UPDATE` z `EMBEDDED_ACTIVITY_UPDATE_V2`), zamknięcie;
     - na początek tylko aktywności w kanale tekstowym (bez dźwięku i obrazu z kanału głosowego);
     - płatne aktywności i gry (SKU, zakupy w aplikacji) odpadają;
     - kod aktywności trzeba odizolować: osobny `WKWebsiteDataStore` bez ciasteczek Discorda, dostęp tylko do domeny aktywności, token OAuth wydany dla tej jednej aplikacji, nigdy token konta, i potwierdzenie przed `AUTHORIZE`.
   - Nie robimy: Questy i sklep Nitro.

---

### 🔜 Etap 14: Reszta do Discorda 1:1
1. **Powiadomienia:** (granica opisana w README 1.11)
   - [ ] Sprawdzić, ile da się wycisnąć z odświeżania w tle na iOS bez łamania zasad.
2. **Wideo:** (nadawanie wideo i ekranu jest w Etapie 9)
   - [ ] Odbiór cudzych kamer i Go Live w kanale głosowym serwera jest napisany (panel nad czatem kanału, szczegóły w CHANGELOG), ale nie był testowany na żywo. Do przeklikania z drugą osobą: kamera, Go Live z dźwiękiem, dwa obrazy naraz, pełny ekran, rozmowa DM, wyłączenie i ponowne włączenie obrazu, dołączenie w trakcie streamu, przejście DAVE, gdy ktoś wchodzi lub wychodzi. Niepewne miejsca, od których zacząć, gdy obrazu nie ma: numer grupy DAVE streamu (`rtc_server_id − 1`), sesja w Identify streamu, prośba o klatkę kluczową i o retransmisję (RTCP PLI i NACK), `any: 100` w Media Sink Wants, typy pakietów 101–104.
   - [ ] AV1 (powody w CHANGELOG; wymaga testu z prawdziwym nadawcą), podgląd streamu przed wejściem, dźwięk streamu w stereo.
   - [ ] Potem własna kamera.
   - [ ] Redukcja szumów mikrofonu w voice (odpowiednik Krisp, np. przetwarzanie głosu z `AVAudioEngine`).
3. **Zarządzanie serwerem (dla moderatorów):** całość zrobiona 1.11 (CHANGELOG, [PL_ONBOARDING_ADMIN_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/PL_ONBOARDING_ADMIN_NOTES.md), [OVERNIGHT2_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/OVERNIGHT2_NOTES.md)). Zostało:
   - [ ] Sekcja „Zarządzanie serwerem” pojawia się dopiero, gdy serwer był otwarty w tej sesji (bez danych o rolach uprawnienia nie są znane).

---

### 🔜 Etap 15: Lepsze niż Discord
Wszystko lokalnie i uruchamiane przez użytkownika. Nic, co samo działa z tokenem konta (automatyczne wysyłanie, masowe pobieranie z wielu serwerów w tle, zaplanowane wiadomości), bo Discord traktuje to jak self-bota. Wtyczki w stylu Vencorda, które modyfikują klienta albo wysyłają nietypowy ruch, też podnoszą ryzyko blokady (samo niewysyłanie wskaźnika pisania do nich nie należy, patrz Paczka D).
1. **Paczka A:** zrobiona 1.11 (galeria, przypomnienia i zapisane, alerty, ghost ping przez usunięcie i przez edycję), szczegóły w `CHANGELOG.md` i [STAGE15A_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/STAGE15A_NOTES.md).
2. **Paczka B (system Apple):** zrobiona 1.11 (Spotlight, widżet, Live Activity, Skróty, Handoff), szczegóły w `CHANGELOG.md` i [PACK_B_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/PACK_B_NOTES.md).
   - [ ] Wybór kanału w „Open Channel” przy uruchomieniu nie ma wyszukiwarki i pokazuje tylko 60 pierwszych (DM-y, potem serwery alfabetycznie); przydałby się najpierw wybór serwera.
3. **Paczka C:** notatki i tagi, eksport do Markdown i PDF, tryb offline zrobione 1.11 ([OVERNIGHT2_NOTES](https://github.com/lakafior/Aicord/blob/efa23601c9df2f55bed5f99ca5902f61bf246732/docs/OVERNIGHT2_NOTES.md)). Zostało:
   - [ ] Codzienny skrót z wybranych kanałów wielu serwerów (rozszerzenie Catch Up), o wybranej porze, z powiadomieniem.
4. **Formatowanie wiadomości:** formatowanie zaznaczenia i „Formatted Message” zrobione 1.11. Zostało:
   - [ ] Później w arkuszu tryb embed z Etapu 16.
5. **Paczka D (opcje znane ze Swiftcorda):** zrobiona 10.11 (prywatność pisania, czyszczenie linków, prywatne nazwy i EXIF, dzielenie długich wiadomości, większe pliki przez wybrany serwis, emoji i naklejki bez Nitro, globalny Quick Switcher na Macu, filtr trybu skupienia), szczegóły w `CHANGELOG.md`. Zostało:
   - [ ] Standardowe paczki naklejek Discorda w zakładce Stickers (dziś tylko naklejki serwerów).
   - [ ] Usuwanie lokalizacji także z filmów (dziś tylko zdjęcia).

---

### 💤 Etap 16: Własny bot w Aicordzie (niski priorytet)
Pomysł na kiedyś. Webhook kanału albo token własnego bota pozwala wysyłać to, czego konto użytkownika nie może (embedy, przyciski, Components V2), i legalnie automatyzować. To zwykły bot, nie self-bot. Wada: działa tylko na serwerach, gdzie można dodać bota albo webhook, więc przyda się głównie właścicielom i moderatorom.
1. **Jednorazowe, uruchamiane przez użytkownika (iOS i macOS):** jedno wywołanie REST, bez gatewaya i bez pracy w tle.
   - [ ] Tryb embed w arkuszu „Formatted Message” (Etap 15.4), w stylu Discohooka: embedy, Components V2, przyciski-linki, obrazki, z podglądem na żywo. Tylko tam, gdzie jest webhook (wklejony URL albo utworzony przez Aicord przy Manage Webhooks, z własną nazwą i awatarem) albo twój bot; konto użytkownika embedów nie wysyła.
   - [ ] Intelligence → wiadomość: podsumowanie kanału albo szkic ogłoszenia z modelu, wysłany jako embed przez webhook lub bota.
2. **Nasłuchujące (tylko Mac włączony całą dobę, drugie połączenie z gatewayem z tokenem bota; na iOS system usypia aplikację):**
   - [ ] Zaplanowane ogłoszenia i przypomnienia, powitania, automatyczne role, role za przyciski lub reakcje.
   - [ ] Intelligence dla wszystkich na serwerze: `/ask`, `/summarize`, `/translate`, odpowiedzi ephemeral.
   - [ ] Logi usuniętych i edytowanych wiadomości dla moderatorów, skrót z kanałów i alerty po słowach w tle, oficjalnie przez intent Message Content.
   - [ ] Prosty kreator komend bez kodu (komenda, odpowiedź, przyciski).
- Podstawa: obsługa interakcji z sesji bot-interactions (`tools/testbot/`, `POST /interactions`). Część modeli bota wycięta w Etapie 7 trzeba przywrócić w `AicordKit`.

---

### 🔜 Etap 12: Wydania — macOS i iOS w GitHub Releases
Na końcu, gdy aplikacja jest stabilna. Przygotowane w nocy 30/31.10 (niczego nie uruchomiono na GitHubie): `release.yml` (iOS, `.ipa`, Release, źródło AltStore na Pages), `release_macos.yml` (szkic podpisu i notaryzacji) i `scripts/altstore_source.py`. Kroki i sekrety: [CONTRIBUTING](.github/CONTRIBUTING.md#releasing).
1. **macOS: podpisana aplikacja z aktualizacjami:**
   - [ ] Dodać sekrety (certyfikat Developer ID jako .p12, klucz API App Store Connect) i sprawdzić `release_macos.yml` na pierwszym tagu (wymaga płatnego konta Apple Developer).
2. **iOS: niepodpisana `.ipa` i źródło AltStore:**
   - [ ] Włączyć GitHub Pages (Source: GitHub Actions) i wypchnąć pierwszy tag `v*`; sprawdzić, że AltStore i SideStore przyjmują źródło i instalują `.ipa`.
   - [ ] Ikona źródła w większym rozmiarze (dziś 128 px z rozszerzenia Safari) i zrzuty ekranu w źródle.
   - [ ] Sprawdzić uprawnienia i rozszerzenia pod darmowe konto: AltStore podpisuje kontem użytkownika, a darmowe konto ma limit 3 App ID, więc każde rozszerzenie (np. Safari z Etapu 8) zjada jedno miejsce. Push i inne uprawnienia płatnego konta nie zadziałają. Rozszerzenie widżetów to trzeci App ID, a podpis AltStore zmienia ID App Group (widżet może zostać pusty).
3. **Opis wydań:**
   - [ ] Instrukcja instalacji w README (link do źródła AltStore). Notatki do wydania są brane z najnowszej sekcji `CHANGELOG.md` automatycznie.
