# Noc 1/2.11.2026: notatki (formatowanie, Paczka C, zarządzanie serwerem)

Gałąź `claude/overnight-2-3b95cf`, jedna sesja, symulator iPhone 18 Pro (`10C26E42…`) zalogowany na prawdziwe konto. Zapisy na koncie tylko na „Aicord Test” (mój serwer testowy). Nie wchodziłam w zakładkę Wiadomości ani w DM-y, nikomu nic nie wysłałam. Nic nie wypchnięte ani scalone. Każda część: build `platform=macOS` i `generic/platform=iOS Simulator` (osobny `-derivedDataPath` w scratchpadzie) bez ostrzeżeń.

## 1. Formatowanie wiadomości (Etap 15.4)

Kod: `Aicord/Common/Chat/Input/MessageFormatting.swift` (logika), `FormattedMessageSheet.swift` (arkusz), poprawki w `iOS/PastableTextField.swift`, `macOS/TextView.swift`, `InputBar.swift`.

- `MessageFormat.edit(in:selection:)`: zwraca jedną edycję (zakres, zamiana, nowe zaznaczenie) w jednostkach UTF-16, więc pasuje do `UITextView`, `NSTextView` i `NSString`. Przełącza: gdy zaznaczenie już ma znaczniki w środku albo tuż obok, zdejmuje je. Kursywa `*` nie myli się z pogrubieniem `**` (na pogrubionym słowie daje `***x***`). Kod z nową linią robi blok ```` ``` ````. Link: zaznaczony tekst staje się etykietą `[tekst](https://)` z zaznaczonym `https://` do nadpisania; zaznaczony adres staje się celem `[](adres)` z kursorem w etykiecie.
- **iOS:** podmenu „Formatowanie” w systemowym menu edycji (`textView(_:editMenuForTextIn:suggestedActions:)`), tylko przy zaznaczeniu. Na klawiaturze sprzętowej ⌘B, ⌘I, ⌘U, ⌘⇧X i ⌘K (`keyCommands` z priorytetem nad systemem). Edycja przez `replace(_:withText:)`, więc działa cofanie.
- **Mac:** to samo podmenu na górze menu pod prawym przyciskiem (z pokazanymi skrótami) i skróty w `performKeyEquivalent`, gdy pole ma fokus. Edycja przez `shouldChangeText`/`didChangeText` (cofanie).
- **Decyzja:** ⌘K bez zaznaczenia zostaje Quick Switcherem (tak jak było); z zaznaczeniem robi link.
- **„Formatted Message”** pod plusem (iOS i Mac): `TextEditor` z zaznaczeniem (`TextSelection`), nad nim rząd wstawek: styl zaznaczenia, nagłówki 1–3 i `-#`, lista punktowana i numerowana, cytat (przełączają prefiks na wszystkich zaznaczonych liniach), blok kodu z 20 językami, znacznik czasu (data, 7 stylów `t/T/d/D/f/F/R`, podgląd i surowy `<t:…>`), wzmianki (osoby wczytane w pamięci serwera albo uczestnicy DM, role z @everyone i @here, kanały, z wyszukiwarką) i emoji (ten sam picker co w polu). Podgląd na żywo przez `MarkdownText` (Textual), obok edytora na szerokim oknie, pod nim na iPhonie. Licznik znaków (2000, z Nitro 4000). Na dole „Do pola tekstowego” i „Wyślij” (⌘↩); wysyłanie idzie tą samą drogą co pole, więc odpowiedź i załączniki z pola zostają.
- Wstawka (wzmianka, emoji, znacznik czasu) dostaje spację przed sobą, gdy przed kursorem jest słowo.

**Sprawdzone w symulatorze** (na „Aicord Test” #general, bez wysyłania): podmenu Formatowanie w menu edycji ze wszystkimi 7 stylami, spoiler na zaznaczeniu (zaznaczenie zostaje na tekście), arkusz z wklejonym tekstem z pola, nagłówek, znacznik czasu z podglądem („Sunday, 1 November 2026 at 23:47”), wzmianka roli @Tester w podglądzie, „Do pola tekstowego”. Pole wyczyszczone, **żadna wiadomość nie została wysłana** (z dozwolonej jednej nie skorzystałam). Logika `MessageFormat` sprawdzona osobnym programem (11 przypadków: przełączanie w obie strony, `***`, blok kodu, polskie znaki, emoji przed zaznaczeniem, link z tekstu i z adresu).

**Niesprawdzone:** Mac (menu pod prawym przyciskiem i skróty; nie klikam w aplikację na Macu), skróty z klawiatury sprzętowej na iPadzie, wysłanie z arkusza.

## 2. Paczka C i drobiazgi

### Eksport kanału (Etap 15.3)
- `Aicord/Common/Chat/ChannelExportSheet.swift`, w menu kanału (•••) jako „Eksportuj kanał…”.
- Zakres: ostatnie 100 / 500 / 1000 / 5000 albo „od daty”. Pobieranie stronami po 100 z przerwą 0,9 s między stronami (5000 wiadomości ≈ 45 s), najwyżej 5000, tylko jeden kanał, tylko na żądanie. Anulowanie przerywa.
- Markdown: tytuł „#kanał · Serwer”, nagłówek z datą eksportu i zakresem, potem `**autor** · data`, treść (wzmianki zamienione na nazwy, emoji jako `:nazwa:`), załączniki jako linki.
- PDF: CoreText, A4, numery stron, czarny tekst (do druku). Działa tak samo na iOS i macOS (bez UIKit/AppKit).
- Plik w katalogu tymczasowym, udostępniany przez `ShareLink` (systemowy arkusz).
- Sprawdzone: eksport #general z „Aicord Test” do PDF; plik obejrzany (tytuł, nagłówek, wiadomość, numer strony). Markdown i wielostronicowy PDF niesprawdzone na żywo (kanał ma jedną wiadomość).

### Prywatne notatki i tagi
- `Aicord/Stores/PersonNotesStore.swift`: notatka i tagi per użytkownik w `UserDefaults`, tylko lokalnie. W profilu sekcja „Prywatna notatka” (pole, tagi z usuwaniem, podpowiedzi istniejących tagów, wspólne serwery z profilu). Na liście członków tagi obok nazwy (dwa i „+N”).
- Sprawdzone: profil autora wiadomości na FashionReps (tylko odczyt): sekcja, wspólne serwery, dodanie i usunięcie tagu. Tagów na liście członków nie oglądałam.

### Tryb offline
- `Aicord/Stores/OfflineCache.swift`: po otwarciu kanału (3 s po ostatniej zmianie listy) zapisuje 100 najnowszych wiadomości jako JSON w Application Support/Offline (wyłączone z kopii zapasowej, na iOS z ochroną pliku). Najwyżej 40 kanałów. Nic dodatkowo nie pobiera.
- Czytnik `OfflineReaderView`: lista kanałów i wiadomości (Markdown, załączniki jako linki). Dostępny z ekranu łączenia („Czytaj zapisane wiadomości”, gdy coś jest zapisane) i z Ustawienia → Zaawansowane → Offline (wyłącznik, czytnik, usuwanie, rozmiar).
- Stan offline: `NetworkMonitor` (`NWPathMonitor`) i kapsuła „Offline” nad czatem.
- Sprawdzone: zapis dwóch kanałów, lista i czytnik w Ustawieniach. **Niesprawdzone:** prawdziwy brak sieci (symulator dzieli sieć z Makiem; nie odcinałam jej) i przycisk na ekranie łączenia.

### Ghost ping przez edycję (Etap 15.1)
- `NotificationStore.handleEdited`: gdy zapamiętana wzmianka (o Tobie, Twojej roli albo everyone) po edycji znika z `mentions`/`mention_roles`/`mention_everyone`, trafia do listy ghost pingów jak usunięcie, z osobnym tekstem powiadomienia. Aktualizacje bez `content` (dociągnięte embedy) są pomijane. W liście ikona ołówka i „Wzmianka usunięta edycją …”. Pole `edited` w zapisie jest opcjonalne, więc stare wpisy dekodują się bez zmian.
- **Niesprawdzone na żywo:** wymaga drugiego konta.

### Powiadomienie o aktualizacji (Etap 12.1)
- `Aicord/Common/System/UpdateChecker.swift`: `GET /repos/lakafior/Aicord/releases/latest` przy starcie najwyżej raz na 24 h, bez tokenu. 404 (brak wydań) = brak banera. Wersje porównywane liczbowo (0.10.0 > 0.9.1), pomija szkice i prerelease. Baner u góry z „Pobierz” i zamknięciem; zamknięte wydanie nie wraca.
- Settings → Advanced → Aktualizacje: wyłącznik, „Sprawdź teraz” z wynikiem.
- Sprawdzone: „Sprawdź teraz” → „Nie ma jeszcze żadnego wydania.” (404). Baneru nie widziałam, bo wydań nie ma.

### README
- Sekcja „About notifications”: push idzie przez APNs Discorda tylko do jego aplikacji; Aicord powiadamia, gdy działa (Mac bez problemu, iOS usypia w tle).
