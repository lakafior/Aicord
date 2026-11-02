# Starsza historia i płynne przewijanie czatu (2 listopada 2026)

Wszystko mierzone w symulatorze iPhone 18 Pro (iOS 27) na długim kanale z obrazkami i wideo, logami `print` w `body` i w `onScrollGeometryChange` (usunięte przed commitem).

## Dlaczego stronicowanie było wyłączone

W Paicordzie (grudzień 2025) `tryFetchMoreMessageHistory` wołał `PlaceholderMessageSet().onAppear` na górze listy. Wyłączono to, bo:

1. **Skok przy każdej stronie.** Po doklejeniu strony u góry SwiftUI **nie koryguje offsetu**: wysokość treści rośnie o ~5000 pt, a `contentOffset.y` zostaje ten sam. Widok przeskakuje więc na świeżo wczytane wiadomości. Nie pomaga ani `scrollPosition(id:)` (zmierzone: ID się nie utrzymuje), ani `defaultScrollAnchor(.bottom, for: .sizeChanges)`, z nim i bez niego jest tak samo. Do tego `fetchMessages(before:)` wołał `requestScrollToMessage(najnowsza z pobranych)`.
2. **Pętla przy otwarciu.** Zanim pierwszy układ osiądzie na dole, `LazyVStack` przez chwilę układa się od góry, więc placeholder dostawał `onAppear` i pobierał stronę za stroną.
3. **Utrata najnowszych.** `trimExtraMessagesIfNeeded(preferRemovingOldest: false)` ustawiał `hasLatestMessages = false` zawsze, także gdy nic nie przycinał.
4. **Nowa wiadomość zjadała historię.** `handleMessageCreate` przycinał do 200 najstarszych, czyli dokładnie te, które czytał ktoś przewinięty w górę.

## Co jest teraz

- **Wyzwalacz:** `onScrollGeometryChange` zwraca `Bool` „do trzech ekranów od góry”, więc nie odświeża `body` na każdej klatce. Pobiera dopiero po pierwszym przewinięciu przez użytkownika (`onScrollPhaseChange`) i tylko gdy treść jest wyższa niż ekran. Gdy strona nie wypełni tych trzech ekranów, po zakończeniu ładowania idzie kolejna (`onChange(of: loadingMessagesTask == nil)`). Wcześniejsza wersja z `onChange(of: messages.keys.first)` stawała: zmiana przychodziła, gdy zadanie jeszcze trwało, a strażnik ją odrzucał.
- **Store:** `tryFetchMoreMessageHistory` pobiera jedną stronę naraz (`loadingMessagesTask`), co najmniej 1 s między stronami (kolejne żądanie czeka resztę sekundy), przez `GET /channels/{id}/messages?before=<najstarsza>&limit=50`. Strona krótsza niż 50 kończy historię (`hasMoreHistory = false`) i pokazuje „Welcome to the start of #…”. U góry jest mały `ProgressView` (44 pt) zamiast 30 placeholderów.
- **Pozycja po doklejeniu:** `ChatView` używa `ScrollPosition` zamiast `scrollPosition(id:)`. Store zapisuje, ile wiadomości doklejono (`unsettledHistoryInsertion`). Pierwszy przyrost wysokości treści, który pasuje do strony (co najmniej 10 pt na wiadomość), przesuwa offset o ten przyrost (`scrollTo(y: offset + przyrost)`), raz. Okno czasowe się nie sprawdziło: `LazyVStack` zgłasza nową wysokość dopiero przy kolejnym ruchu, czasem po ponad 0,5 s, często razem z ruchem palca. Mniejsze zmiany to doprecyzowanie szacunków wysokości, które SwiftUI już sam trzyma w miejscu. Ich kompensowanie dawało podwójne skoki (zmierzone).
- **Blisko dołu:** liczone z geometrii (`awayFromLatest`: ponad ekran od dołu), a nie z ID wiersza. Steruje strzałką „na dół”, potwierdzaniem przeczytania i przycinaniem.
- **Limity:** przy czytaniu historii mieści się do 1000 wiadomości (`HistoryMessageLimit`). Nowe wiadomości przycinają najstarsze do 200 tylko wtedy, gdy na ekranie są najnowsze (`isViewingLatest`).

Sprawdzone w symulatorze: wolne przeciągnięcia (bez bezwładności) przez kilka stron dają ciągłe daty, bez dryfu po zatrzymaniu. Szybkie gesty przez 4 strony: każda skompensowana, także przy odbiciu na samej górze (offset −191 → 4880). Krótki kanał kończy się nagłówkiem „Welcome to the start of #guides”, a strzałka „na dół” wraca do najnowszych.

## Pozostałe przyczyny szarpania

Liczone wywołania `body` przy dwóch wolnych przeciągnięciach po ~800 pt w najnowszej części kanału:

1. **`scrollTargetLayout()` + pozycja przewijania przeliczały cały czat co wiersz.** Ze `scrollTargetLayout` pozycja śledzi wiersz przy kotwicy, a jej stan należy do `ChatView`, więc każdy mijany wiersz przeliczał `ChatView.body`, czyli `ForEach` i każdy widoczny `MessageCell`. Pomiar: **9 wywołań `ChatView.body` ze `scrollTargetLayout`, 1 bez niego.** `scrollTo(id:)` działa bez niego (strzałka „na dół” sprawdzona). Commit 710edbd przeniósł tylko odczyt pozycji do przycisku, ale stan dalej należał do `ChatView`.
2. **`body` czatu czytał członków serwera.** `hasPermission` czyta `memberBoxes` (cały słownik), więc każdy dociągnięty członek (autorzy ze strony historii, lista członków) odświeżał cały `ChatView`. Nagłówek historii (`HistoryEdge`) i pasek wpisywania (`ChatComposer`) są teraz osobnymi widokami. Pomiar: po „Received members chunk” odświeżają się tylko `HistoryEdge` i `ChatComposer`, `ChatView` nie.
3. **`LazyVStack` w `EmbedsView`.** Leniwy stos wewnątrz wiersza leniwej listy zgaduje swoją wysokość, dopóki nie jest na ekranie, więc wiersz z embedami zmieniał rozmiar przy wjeździe. Teraz to `VStack`.
4. **`DefaultMessage ==` pomijał `inline`.** Po doklejeniu starszych dotąd pierwsza wiadomość może zmienić grupowanie, a `equatable()` zostawiał stary wygląd. `inline` jest teraz w porównaniu.

Sprawdzone i **nie** będące przyczyną:

- `MarkdownText` zapisuje `frame(in: .global)` do `@State documentFrame` przy każdej klatce. `body` tego nie czyta, więc widok się nie odświeża. Pomiar: 8 wywołań `MarkdownText.body` ze starym kodem, 7 z wersją bez `@State`. Zostawione bez zmian.
- Obrazki i wideo w załącznikach i embedach mają zarezerwowany rozmiar (`AttachmentSizedView` z `aspectRatio` z API, karta wideo `aspectRatio` 16:9 albo z API), awatary mają stałą ramkę.

## Nie zrobione / do sprawdzenia

- macOS: zbudowane, nie przeklikane (zakaz klikania w żywą aplikację na Macu). Wyzwalacz używa `onScrollPhaseChange(...).isScrolling`, które powinno łapać kółko i gładzik.
- `MessageTranslationView` czyta cały słownik `translator.states`, więc przy automatycznym tłumaczeniu każda zmiana stanu odświeża wszystkie widoczne tłumaczenia. Dotyczy tylko włączonego auto-tłumaczenia.
- Gdy powyżej 1000 wiadomości przycinany jest dół, strzałka „na dół” dociąga najnowsze od nowa (`returnToLatest`).
- Bardzo szybkie gesty potrafią dojść do szczytu przed kolejną stroną (jedna strona ~5000 pt, najwyżej jedna na sekundę). Widać wtedy przez chwilę spinner, a pozycja po doklejeniu zostaje.
