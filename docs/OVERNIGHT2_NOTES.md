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

## 3. Zarządzanie serwerem (Etap 14.3)

Kod: `Aicord/Common/Guilds/Admin/ServerAdminMore.swift` (nowe widoki), zmiany w `ServerAdmin.swift` i `ServerSettingsSheet.swift`. W `AicordKit`: model i payload AutoModa (`Types/AutoMod.swift`), endpointy `/auto-moderation/rules` i `POST /guilds/{id}/delete`, `clearGuildRoleIcon` (jawne `null`), poprawka walidacji naklejki (pusty opis jest dozwolony).

- **Nadpisania uprawnień:** w edytorze kanału i kategorii „Uprawnienia” (z Manage Roles). Lista nadpisań z liczbą dozwolonych i zabronionych, „+” dodaje rolę albo osobę (wczytaną w pamięci serwera). Edytor ma dla każdego uprawnienia kanału trzy stany (zabroń, dziedzicz, zezwól); uprawnienia tylko serwerowe są pominięte. „Usuń nadpisanie” z potwierdzeniem.
- **Kolejność:** kategorie w arkuszu „Kolejność kategorii” (menu „+” w Kanałach), role przeciąganiem na liście ról. Ról na i ponad twoją najwyższą nie da się przesunąć (komunikat), @everyone jest osobno na dole (jego uprawnienia nadal się edytuje).
- **Pełna lista uprawnień roli:** wszystkie 50 w grupach jak w Discordzie (`PermissionCatalog`), także w nadpisaniach.
- **Ikony ról:** emoji albo obraz PNG/JPEG do 256 KB, „Usuń ikonę”. Tylko na serwerach z funkcją `ROLE_ICONS`.
- **AutoMod:** lista reguł z wł./wył., nowe reguły czterech rodzajów (własne słowa do 6, często zgłaszane słowa, spam wzmiankami, podejrzany spam), reakcje (blokada z komunikatem, alert na kanał, timeout przy słowach i wzmiankach), pomijane role i kanały, usuwanie z potwierdzeniem.
- **Emoji i naklejki:** lista, wgrywanie z plików (emoji: PNG, JPEG, GIF, WebP do 256 KB; naklejki: PNG, GIF do 512 KB z tagiem), nazwa w alercie, usuwanie (przesunięcie albo menu) z potwierdzeniem.
- **Usuwanie serwera:** sekcja tylko dla właściciela, alert z wpisaniem nazwy (przycisk aktywny dopiero przy zgodnej nazwie). **Ważne:** `DELETE /guilds/{id}` z konta użytkownika kończy się zerwaniem połączenia (-1005); klient Discorda używa `POST /guilds/{id}/delete`, przy 2FA Discord odsyła 60003 i aplikacja pokazuje wspólny arkusz MFA.

**Sprawdzone w symulatorze na „Aicord Test”** (mój serwer, jedyny członek): reguła AutoModa utworzona, odczytana i usunięta; nadpisanie roli Tester (zabronione „Tworzenie zaproszeń” na #general) zapisane i usunięte; kategorie zamienione miejscami i przywrócone; nowa rola przeciągnięta nad Tester i usunięta; emoji wgrane i usunięte; naklejka wgrana i usunięta (pierwsza próba odrzucona przez walidację pustego opisu, poprawione); pełna lista uprawnień w edytorze roli.

**Usuwanie:** utworzyłam osobny serwer „Aicord Delete Test” (od zera). Pierwsza próba (`DELETE`) dała „Połączenie sieciowe zostało utracone”, druga (`POST …/delete`) doszła do arkusza MFA. Kodu z aplikacji uwierzytelniającej nie mam, więc zamknęłam arkusz; **serwer „Aicord Delete Test” został** (do usunięcia rano z kodem: Ustawienia serwera → Usuń serwer, albo w Discordzie). „Aicord Test” i NAScin nietknięte poza testami wyżej (wszystko przywrócone).

**Niesprawdzone:** ikony ról (Aicord Test nie ma `ROLE_ICONS`), nadpisanie dla osoby (jestem jedynym członkiem, właściciela nadpisania nie dotyczą), Mac, usunięcie do końca z kodem.

**Znalezione przy okazji:** sekcja „Zarządzanie serwerem” w ustawieniach serwera pokazuje się dopiero po otwarciu serwera w tej sesji (wcześniej też tak było). Selektor plików na iOS potrafił się nie otworzyć, gdy prosiło o niego menu jeszcze w trakcie zamykania: start po 0,4 s.

## Stan symulatora po nocy

- Wyłącznik powiadomień Aicorda (wyłączony na czas testów, bo banery z innych serwerów przechwytywały stuknięcia i raz otworzyły regulamin FashionReps, nic nie zaakceptowałam) przywrócony.
- Pliki testowe PNG i PDF usunięte. Zostały: 2 zapisane kanały offline (funkcja), data ostatniego sprawdzenia aktualizacji.
- Na koncie: serwer „Aicord Delete Test” (patrz wyżej). Na NAScin nic nie zmieniałam i nic nie wysłałam.

## Podsumowanie

| Część | Commity | Stan |
|---|---|---|
| 1. Formatowanie | `f6ebea2`, `39f3ec4` | zrobione; iOS sprawdzony, Mac nie |
| 2. Paczka C i drobiazgi | `37041a1` | zrobione; offline bez prawdziwego braku sieci, ghost ping przez edycję bez drugiego konta |
| 3. Zarządzanie serwerem | `26c2216`, `23f0e13` | zrobione; usuwanie zatrzymane na kodzie 2FA, ikony ról niesprawdzone |

Każdy commit: build macOS i iOS Simulator bez nowych ostrzeżeń. `swift test`: AicordKit 152, Textual 187. Polskie napisy: ok. 180 nowych, z odmianą liczby mnogiej tam, gdzie jest liczba.

## Dodatkowo: czarny ekran po wybraniu serwera z wyszukiwarki

- **Przyczyna:** wynik „serwer” w Szukaj wołał `open(guild:channel: nil)`, a na iPhonie `onOpen` zawsze wysuwał czat (`chatOpen = true`). Serwer bez zapamiętanego kanału ma `selectedChannel == nil`, więc w panelu czatu był `Color.clear` („never shown”), czyli czarny ekran nad zakładką Szukaj. Gdy kanał był zapamiętany, otwierał się on zamiast serwera.
- **Poprawka:** `SearchView` ma osobne `onOpenServer`; na iPhonie przełącza na zakładkę Home z listą kanałów wybranego serwera, bez wysuwania czatu. Wyniki-kanały i wiadomości działają jak wcześniej.
- **Mac i iPad:** Szukaj jest tam arkuszem, `onOpen` tylko go zamyka, a bez kanału baseplate pokazuje `ContentUnavailableView`, więc czarnego ekranu nie było; ścieżka bez zmian (build macOS zielony, nie klikane).
- Sprawdzone w symulatorze: Szukaj → „Aicord Delete” → serwer → Home z kanałami „Aicord Delete Test”.
- Przy okazji zauważone (nie poprawiane): na świeżym serwerze kategorie z tą samą pozycją (0) potrafią zamienić się miejscami między uruchomieniami, bo sortowanie nie ma drugiego klucza.

## Dodatkowo: skaczące przewijanie czatu

Odtwarzane w symulatorze na publicznym kanale FashionReps #jaki-batch (dużo obrazów) i #general-offtopic, tylko przewijanie, nic nie klikane ani nie wysyłane.

**Pomiar:** tymczasowy licznik wywołań `MessageCell.body` i `ChatView.body` (nie wszedł do commita), ten sam scenariusz: otwarcie kanału, 4 przeciągnięcia w górę, 4 w dół.

| | `MessageCell.body` przy przewijaniu | `ChatView.body` |
|---|---|---|
| przed | 42 | 19 |
| po | 6 | 21 |

Do tego narzędzie porównujące kolejne zrzuty co 0,25 s (przesunięcie treści w pikselach): po poprawce przewijanie w górę i w dół kończy się płynnym wyhamowaniem, bez skoku po zatrzymaniu. Lista kanałów też (bez zmian w kodzie).

**Przyczyny i zmiany** (`ChatView.swift`):
1. `isScrolling` (faza przewijania) szło do każdej `MessageCell`, więc każdy początek i koniec przewijania przeliczał wszystkie widoczne wiersze, w tym Textual z markdownem, w środku gestu. Potrzebuje tego tylko podświetlenie po najechaniu na Macu: na iOS już nie jest przekazywane ani ustawiane.
2. Strzałka „na dół” i `.onChange(of: currentScrollPosition)` czytały pozycję przewijania w `body` czatu, a `scrollPosition(id:)` zmienia ją przy każdym mijanym wierszu. Przeniesione do osobnego widoku `JumpToLatestButton`, więc zmiana pozycji odświeża tylko przycisk.
3. `.animation(..., value: orderedMessages)` animowało każdą zmianę w wiadomościach (reakcja, edycja, dociągnięty embed, członek z gatewaya) i za każdym razem porównywało całą tablicę wiadomości. Zmiana wysokości wiersza w trakcie przewijania była animowana i przesuwała treść. Teraz animuje tylko pojawienie się nowej najnowszej wiadomości (`vm.messages.keys.last`).

**Sprawdzone bez zmian:** obrazy w załącznikach i embedach mają ramki z `width`/`height` (`AttachmentSizedView`, `aspectRatio`), emoji i awatary stałe wymiary, `id` wierszy to stabilne ID wiadomości.

**Znalezione, nie zmienione:** czat w ogóle nie dociąga starszej historii przy przewijaniu w górę (autor oryginału zakomentował wywołanie `tryFetchMoreMessageHistory` w grudniu 2025, „partial pagination support”), więc skoków przy doładowaniu dziś nie ma, ale po ~50 wiadomościach lista się kończy. Przywrócenie stronicowania z zachowaniem pozycji to osobna praca (punkt w ROADMAP). Listy członków nie mierzyłam. Instruments nie używałam (liczniki i zrzuty wystarczyły do znalezienia przyczyn).
