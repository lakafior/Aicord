# Etap 15, Paczka A: galeria, przypomnienia i zapisane, alerty

Notatki z sesji 1.11.2026 (gałąź `claude/stage15a-gallery-reminders-d30186`, od main `bfb90b5`). Wszystko lokalne i uruchamiane przez użytkownika; nic nie wysyła wiadomości samo i nic nie pobiera w tle.

## Krok 0: ostrzeżenia

- `SystemMessage.swift`: przestarzały `Text + Text` (iOS 26) zamieniony na interpolację `Text("\(a) \(b)")`, z zachowaną czcionką i kolorem znacznika czasu. Osobny commit.
- Po buildach `platform=macOS` i `generic/platform=iOS Simulator` nie zostały inne ostrzeżenia w naszym kodzie. W logu jest tylko `appintentsmetadataprocessor` („no AppIntents.framework dependency”), który pochodzi z narzędzia, a nie z kodu.

## Galeria (`Aicord/Common/Chat/ChannelGallery.swift`)

- `ChannelGallerySheet`: zakładki Media, Links i Files. Media to siatka kwadratowych miniatur (filmy pokazują pierwszą klatkę przez `format=png` i znaczek ▶). Links i Files to listy z autorem i datą, każdy wiersz ma przycisk „Go to Message”, a menu kontekstowe to samo.
- Dane: najpierw `gw.loadedMessages(in:)`, czyli już wczytana historia. Potem jedna strona wyszukiwania z `has:` przy otwarciu zakładki i kolejne strony, gdy przewiniesz do ostatniego elementu (albo przez „Load More”). Serwer korzysta z `searchGuildMessages` z `channel_id`, DM z `searchChannelMessages`. Media to `has=image&has=video`, czyli lub: na #jaki-batch wyszło 61 zdjęć i filmów. Wiadomości z obu źródeł są łączone po ID.
- Elementy: załączniki `image`/`video` i osadzenia typu `image` (obraz albo miniatura) oraz `gifv` (wideo). Linki są wykrywane `NSDataDetector` w treści, a tytuł pochodzi z osadzenia o tym samym URL. Pliki to załączniki audio i inne.
- Stuknięcie miniatury otwiera istniejący `AttachmentViewer` z wszystkimi mediami zakładki na właściwej pozycji. `AttachmentViewer` dostał wewnętrzny `init`, a galeria pokazuje go sama (`fullScreenCover` na iOS, nakładka na Macu), bo główny modyfikator siedzi pod arkuszem.
- Spoilery (`SPOILER_`, flaga `isSpoiler`) i media oznaczone przez Discord jako wrażliwe mają w siatce rozmytą miniaturę z ikoną; podgląd po stuknięciu pokazuje je normalnie, jak w czacie po odsłonięciu.
- Wejścia: menu „…” w nagłówku czatu (teraz zawsze menu: Pinned Messages, Media Links and Files, Threads), menu kontekstowe kanału na liście oraz przycisk „Media, Links and Files” w profilu (popover), gdy z tą osobą jest DM.
- **Naprawione przy okazji:** `AttachmentViewer` na iOS miał `TabView(selection: Int?)` z tagami `Int`, więc przy kilku załącznikach zawsze startował od pierwszego. Teraz tag ma typ `Int?`, co poprawia też podgląd w czacie. Druga pułapka: wysoki obraz wystawał poza komórkę siatki i przechwytywał stuknięcia sąsiadów, dlatego obraz ma `allowsHitTesting(false)`.

## Przypomnienia i zapisane

- `Aicord/Stores/SavedItemsStore.swift`: `MessageSnapshot` przechowuje ID, kanał, serwer, autora (pseudonim z serwera, gdy jest wczytany), awatar, miejsce („#kanał · Serwer” albo „DM with …”), tekst do 600 znaków i datę. Store `SavedItemsStore.shared` trzyma zapisane, przypomnienia i ghost pingi w `UserDefaults` jako JSON (`Paicord.Saved.*`), na wzór `PinnedPlacesStore`.
- Menu wiadomości (`EntityContextMenu`, sekcja z Mark Unread) ma „Remind Me” (In 1 Hour, In 3 Hours, Tomorrow Morning o 9:00, Custom Time…) oraz „Save Message” albo „Remove from Saved”. Własny czas otwiera arkusz `ReminderTimeSheet` (`appState.reminderTarget`, modyfikator `.reminderSheet()` przy `forwardSheet`).
- Przypomnienie to `UNCalendarNotificationTrigger` z ID `reminder-<uuid>` i `userInfo` (`channel`, `guild`, `message`, `jump=1`). Stuknięcie w `NotificationStore.handle` wywołuje `appState.open(guild:channel:message:)`, który skacze do wiadomości i ją podświetla. Gdy uprawnienia nie było, pierwsze przypomnienie o nie pyta.
- Lista `SavedItemsView` ma zakładki Saved, Reminders (Upcoming i Past) oraz Ghost Pings. Usuwanie działa przesunięciem albo z menu kontekstowego; usunięcie przypomnienia kasuje też zaplanowane powiadomienie. Na iPhonie lista jest w zakładce Messages jako „Saved, Reminders and Ghost Pings”, na Macu i iPadzie jako skrót „Saved” nad DM-ami (arkusz).
- **Naprawione przy okazji:** stuknięcie w powiadomienie trafiało do `AicordAppState.instances.values.first`. W słowniku jest też `sharedEphemeral` (domyślna wartość środowiska) i stany, które SwiftUI utworzył i porzucił, więc zwykle nic się nie działo. Teraz jest `AicordAppState.main`, ustawiane w `RootView`, a obejściem jest pierwszy stan inny niż `sharedEphemeral`. Dotyczy też zwykłych powiadomień o wiadomościach.

## Alerty (`Aicord/Stores/AlertRules.swift`, `NotificationStore`)

- Wszystko działa w `NotificationStore.handleMessageCreate` i na zdarzeniach `MESSAGE_DELETE` i `MESSAGE_DELETE_BULK`, które aplikacja i tak dostaje. Nie ma żadnych dodatkowych zapytań.
- **Słowa kluczowe i regexy:** `AlertRules.KeywordRule` ma wzorzec, przełącznik „Regular Expression”, przełącznik „On” i miejsca: serwery i kanały z istniejącej `NotificationPlaceList`, a pusta lista oznacza wszędzie, łącznie z DM. Słowo pasuje jako całe słowo bez względu na wielkość liter, regex też ignoruje wielkość liter. Skompilowane wyrażenia są w pamięci podręcznej.
- **Osoby do obserwowania:** lista ID z istniejącej `NotificationPeopleList`.
- Alert powiadamia także tam, gdzie ustawienia Discorda milczą (wyciszony serwer, „Only Mentions”). Gdy wiadomość i tak dałaby powiadomienie, jest tylko jedno, z dopiskiem w podtytule („Keyword: …” albo „Watched person”). Obowiązują zwykłe wyjątki: główny przełącznik powiadomień, @silent, zablokowani, filtr słów i kanał, który właśnie oglądasz.
- **Ghost pingi:** wiadomość od kogoś innego z twoją wzmianką, `@everyone`/`@here` albo twoją rolą trafia do pamięci (najwyżej 6 h i 300 wpisów). Jej usunięcie dodaje wpis do listy Ghost Pings i wysyła powiadomienie „Ghost Ping” z autorem, miejscem i treścią (przy podglądzie innym niż pełny bez treści). Domyślnie włączone; przełącznik jest w Settings → Notifications → Aicord Alerts.
- Ustawienia: nowa sekcja „Aicord Alerts” w Settings → Notifications z „Ghost Pings”, „Keywords and Patterns” i „People to Watch”.
- **Pułapka:** edytor reguły dostawał `Binding` z `ForEach($rules)`, a po dodaniu reguły przyciskiem `navigationDestination` trzymało stary indeks i wpisany tekst się nie zapisywał. Teraz edytor dostaje ID i sam szuka reguły w store.

## Testy

- Buildy `platform=macOS` i `generic/platform=iOS Simulator` (`-derivedDataPath` w scratchpadzie) przechodzą bez ostrzeżeń w naszym kodzie.
- Symulator iPhone 18 Pro, konto zalogowane wcześniej. Zrzuty są w notatkach grupy: `side-session-notes/…/stage15a-shots/`.
  - Galeria: #jaki-batch (FashionReps, tylko odczyt) pokazuje 61 elementów w Media; podgląd otwiera stuknięte zdjęcie; w Links widać tytuły i adresy; „Go to Message” otwiera kanał z podświetloną wiadomością. Galeria DM z Kaopejem przez wyszukiwanie w kanale pokazała jedno zdjęcie.
  - Zapisane: „Save Message” dodaje wpis, a lista pokazuje autora, kanał, datę i treść.
  - Przypomnienie: „Custom Time…” na 17:29 przychodzi jako „Reminder” z autorem i kanałem. Stuknięcie w baner w aplikacji otwiera #jaki-batch na tej wiadomości, z podświetleniem. Sprawdzone na kopii przypomnienia z tym samym `userInfo` wysłanej przez `simctl push`, bo prawdziwy baner znikał, zanim zdążyłem go stuknąć. Stuknięcie na ekranie blokady symulatora nie otwierało aplikacji: to zachowanie symulatora, nie Aicord.
  - Alert na słowo kluczowe: reguła „the” (wszędzie) dała powiadomienie „Keyword: the · #🛠 · infinidysk-develo…” z wiadomości na serwerze z ustawieniem „Only Mentions”. Testowa reguła została potem usunięta.
- **Ghost ping na NAScin niesprawdzony.** Z jednego konta nie da się go wywołać, bo własne wiadomości są celowo pomijane: ghost pingiem jest tylko cudza wzmianka. Logikę obejrzałem w kodzie, a test wymaga drugiego konta, które wspomni to konto na NAScin i usunie wiadomość.
- **Incydent:** w DM z Kaopejem moje stuknięcie w miejsce „…” trafiło w przycisk połączenia (w DM pasek ma „…” i słuchawkę), więc wystartowało połączenie. Rozłączyłem je po 7 sekundach. W DM została linia systemowa „Lakafi started a call that lasted 7 seconds”, której nie da się usunąć.

## Do zrobienia

- Ghost ping z drugiego konta na NAScin.
- Ghost ping przez edycję, gdy wzmianka znika z treści (dziś tylko usunięcie wiadomości).
