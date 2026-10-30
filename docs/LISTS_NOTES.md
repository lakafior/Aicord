# Natywne listy: Home (serwery i kanały) i lista członków

Gałąź `claude/native-lists-c389bf`, cztery commity od `03eec5c`. Niescalona, niewypchnięta.
Buildy iOS (symulator) i macOS przechodzą po każdym commicie.

## Co się zmieniło

- **Kanały** (`GuildView`, `ChannelButton`, `VoiceChannelButton`, `HomeView`) to `List(selection:)`.
  Kategorie są `Section(isExpanded:)`. Zaznaczenie bieżącego kanału jest systemowe, a przypięte
  kanały są w pierwszej sekcji razem z kanałami bez kategorii.
- **Wiersze**: `Label` (ikona i nazwa), kropka nieprzeczytanych w lewym marginesie, pogrubienie
  nieprzeczytanych, `MentionCountBadge` z prawej. Ukryte kanały mają kłódkę i otwierają arkusz
  `HiddenChannelInfo`. Kanał głosowy to osobny wiersz, a pod nim po jednym wierszu na uczestnika,
  z kółkiem mówienia.
- **Nagłówek serwera**: pierwsza sekcja z banerem na całą szerokość, a na iPhonie także z nazwą
  i liczbą członków. Ma podpięte istniejące menu serwera (`guildContextMenu`).
- **DM-y** (`DMsView`: pasek DM na Macu i iPadzie) to ta sama lista z tym samym zaznaczeniem.
  Skróty (Friends, Search, Requests, Spam) są w pierwszej sekcji.
- **Lista członków** (`GuildMemberList`, `GroupDMsMemberList`, `MemberRowView`) to `List`
  z sekcją na każdą grupę ról: nagłówek „Rola — liczba”, offline przygaszeni. Zakresy do
  `requestMemberListRange` liczy teraz `onAppear` wierszy zamiast `scrollPosition`.
- Usunięte: zaokrąglony kontener z tłem i maską w `HomeView`, `roundedCorners` w `GuildView`
  i `DMsView`, ręczne tła hover i zaznaczenia w wierszach, `CategoryButton`
  i `isFirstInChannelList`.

## Decyzje

1. **iPhone: `.plain`, nie `.sidebar`.** Najpierw był `.sidebar`, który w kompaktowej szerokości
   rysuje karty `insetGrouped` na czarnym tle. Podczas pracy poprosiłeś o mniej pustego miejsca,
   a potem o odejście od czarnego tła OLED, z listą utworów Apple Music jako wzorem. Dlatego teraz
   `.plain`: wiersze na całą szerokość, przypięte nagłówki sekcji z materiałem i tło motywu
   aplikacji (`scrollContentBackground(.hidden)`). Lista ma to samo tło co pasek serwerów,
   więc znikł też szew między dwoma odcieniami. Zrzut pierwszej wersji z kartami:
   `native-lists-shots/after-v1.png`.
2. **Mac i iPad: `.sidebar`.** Tam lista siedzi w kolumnie sidebar `NavigationSplitView`,
   więc systemowy pasek boczny jest właściwy: zwijanie sekcji, zaznaczenie i wibracja.
   Wszystko to jest w jednym modyfikatorze `channelListStyle()`, a wybór zależy od
   `userInterfaceIdiom`.
3. **Zwijanie na iPhonie.** Lista `.plain` nie zwija sekcji sama, a tapnięcie nagłówka nic nie
   daje (sprawdzone). Dlatego nagłówek kategorii na iPhonie (`GuildView.CategoryHeader`) jest
   przyciskiem z obracaną strzałką, który przełącza to samo `Section(isExpanded:)`.
   VoiceOver dostaje cechę nagłówka i wartość „Expanded/Collapsed”. Na Macu i iPadzie zostaje
   systemowa strzałka paska bocznego.
4. **Zapamiętywanie zwiniętych.** Klucz bez zmian: `"GuildCategory.\(channel.id).Collapsed"`.
   Interpolacja daje `GuildCategory.Snowflake<DiscordChannel>("…").Collapsed`, tak jak dotąd,
   więc stare ustawienia działają. Stan jest w `@State Set` wczytywanym przy zmianie serwera.
5. **Zaznaczenie i otwieranie czatu.** Binding `ChannelButton.selection(appState)` ustawia
   `selectedChannel` i na iOS `chatOpen = true` (dawniej `toggle()`). Ponowne tapnięcie już
   zaznaczonego kanału też otwiera czat (sprawdzone). Wiersze, które nie otwierają czatu
   (głosowe, ukryte, forum/stage/media, uczestnicy, skróty DM, nagłówek), mają `selectionDisabled()`.
6. **Gęstość na iPhonie.** `defaultMinListRowHeight` 36 i pionowe wcięcia wierszy 6 pt
   (`channelListRow()`). Separatory w wierszach kanałów są ukryte, jak w pasku bocznym.
7. **Tło wiersza a zaznaczenie.** Przezroczyste tło wiersza na iPhonie (żeby było widać tło
   motywu) wyłącza też systemowe tło zaznaczenia. Dlatego zaznaczony wiersz dostaje
   `listRowBackground` z systemowym `.fill.secondary`. To jedyne „ręczne” tło i jest
   semantyczne, a nie kolorem z palety.
8. **Pasek serwerów.** Na iOS bez zmian (był już zwykłym `ScrollView` z miękką krawędzią).
   Na Macu próbowałem zamienić `ScrollFadeMask` na `scrollEdgeEffectStyle(.soft)`, ale ikony
   wtedy prześwitywały pod paskiem profilu, który nie ma własnego tła. Maska zostaje.
   `reverseMask` przy odznakach wzmianek też zostaje, bo system nie daje wycięcia pod odznaką.
9. **Kanały, których Aicord nie otwiera** (forum, media, stage) są przygaszone (`opacity 0.5`)
   i nie dają się zaznaczyć, jak dawniej `.disabled(true)`. Menu kontekstowe nadal działa.
   Wątków nie było na liście kanałów przed zmianą i nadal ich tam nie ma.
10. `PlaceContextMenus.swift` jest nietknięty: wiersze tylko podpinają istniejące
    `channelContextMenu` i `guildContextMenu`.

## Sprawdzone (symulator iPhone 18 Pro, prawdziwe konto, tylko oglądanie)

- Lista kanałów w jasnym i ciemnym motywie: baner, nazwa, sekcje, przypięte nagłówki
  przy przewijaniu, przewijanie pod szklanym paskiem kart.
- Nieprzeczytane (kropka i pogrubienie) oraz odznaki wzmianek.
- Zwijanie i rozwijanie kategorii, zapis klucza w UserDefaults. Stan przywrócony.
- Tap otwiera czat, „wstecz” wraca, ponowny tap tego samego kanału znów otwiera czat.
- Menu kontekstowe kanału (przytrzymanie), Pin to Top i Unpin from Top. Stan przywrócony:
  `Paicord.Pinned.*` są puste, jak na początku.
- Show Hidden Channels: kanał z kłódką otwiera arkusz z tematem i informacją, kto może go
  oglądać. Ustawienie wyłączone z powrotem.
- NAScin, kanał głosowy „Ogólne”: dołączenie, wiersz uczestnika pod kanałem, rozłączenie.
- Dynamic Type: rozmiar XXL powiększa wiersze. Rozmiar przywrócony na „large”.
- VoiceOver (drzewo dostępności): nagłówki kategorii są przyciskami z wartością
  „Expanded/Collapsed”, a nieprzeczytane kanały mają wartość „Unread”.
- Mac (przed przełączeniem iPhone’a na `.plain`; kod Maca od tego czasu się nie zmienił):
  pasek DM ze skrótami, lista kanałów jako sidebar z zaznaczeniem, lista członków z sekcjami
  „Online — 7 / Offline — 5”, przygaszonymi offline i nameplate’ami.
- Na koniec motyw aplikacji ustawiony na „Automatic” (na początku był „Dark”).

## Czego nie sprawdzono

- **iPad.** Symulatory iPada nie są zalogowane, a logowanie nie wchodziło w grę. iPad dzieli kod
  z Makiem (sidebar i inspektor z listą członków), ale nie widziałem go na żywo.
- **Kółka mówienia.** Nikt nie mówił w kanale, więc pierścienia nie było widać. Kod
  `participantRow` jest bez zmian poza wcięciem.
- **Przewijanie długiej listy członków na Macu.** Widziałem tylko mały serwer (12 osób).
  Doładowywanie zakresów przy przewijaniu dużego serwera (tysiące osób) nie było testowane.
  To główne ryzyko, patrz niżej.
- **Przypinanie serwerów** (`GuildScrollBar`, kod bez zmian), folderów i pełnego testu
  VoiceOver z czytnikiem.
- **Mac po ostatnich commitach.** Build przechodzi, ale od wyłączenia mojej instancji nie
  oglądałem go ponownie. Zmiany po tym momencie dotyczą tylko iPhone’a (`idiom == .phone`)
  i przygaszenia kanałów forum/stage.

## Ryzyka

- **Doładowywanie listy członków.** `scrollPosition(id:)` nie działa z `List`, więc „gdzie
  jestem” to indeks ostatniego wiersza, który się pojawił (`onAppear`). Przy szybkim
  przewijaniu w górę zakresy liczą się od górnej krawędzi, a nie od dolnej, ale `scrollPairs`
  i tak bierze bieżący i poprzedni blok po 100. Warto przewinąć duży serwer na Macu.
- **Wiersze-zaślepki.** Niewczytany członek to pusty wiersz o wysokości 32 pt, żeby pasek
  przewijania się nie przesuwał. Członek bez `user` daje pusty wiersz.
- **Konflikt z drugą sesją.** Sesja invites-pack instalowała równolegle swoją wersję na tym
  samym symulatorze (dwa razy nadpisała moją w trakcie testu). Przed każdym testem
  reinstalowałem swoją wersję i sprawdzałem, czyj build jest zainstalowany. Na symulatorze
  może teraz być dowolna z dwóch wersji.
- **Otwarcie kanału oznacza go jako przeczytany.** Podczas testu otwierania czatu otworzyłem
  #news (FashionReps) i #w-czym-mogę-pomóc (Kaotober, na Macu). To zwykły ack odczytu na koncie,
  nic nie zostało wysłane.

## Zrzuty

Kopie w folderze notatek grupy (scratchpad sesji jest tymczasowy):
`~/Library/Application Support/Claude/side-session-notes/local_db893067-dd3e-4a79-8f0d-4803e85c882e/native-lists-shots/`

- Przed: `before-home-dark.png`, `before-home-light.png`
- Po (iPhone, `.plain`): `after-home-dark.png`, `after-home-light.png`, `after-scrolled-light.png`,
  `after-plain-collapsed-dark.png`
- Po (pierwsza wersja `.sidebar` z kartami, do porównania): `after-v1.png`
- Menu i przypinanie: `after-channel-menu-dark.png`, `after-pinned-dark.png`
- Ukryte kanały: `after-hidden-light.png`, `after-hidden-info-light.png`
- Głos: `after-voice-light.png`. Dynamic Type: `after-dynamic-type-xxl.png`
- Mac: `after-mac.png` (DM-y), `after-mac-guild.png` (kanały i lista członków)

Oryginały w pełnej rozdzielczości:
`/private/tmp/claude-501/-Volumes-wew-Git-Paicord--claude-worktrees-native-lists-c389bf/13e6d87a-5925-4ba2-b932-a19c99e4aa2c/scratchpad/shots/`

## Proponowane wpisy do dokumentacji (naniesiesz przy scalaniu)

**ROADMAP, Etap 8, punkt 8:** odhaczyć „kontener kanałów” i „Widok serwerów i kanałów od nowa”.
Do zostawienia jako otwarte: sprawdzenie na iPadzie i przewijanie dużej listy członków.

**SHIPPED.md:**

> Home and the member list are native lists: channels are a sidebar on Mac and iPad and an Apple Music–style plain list on iPhone, with collapsible categories that remember their state, system selection, and no custom containers or masks, so corners and backgrounds match in light and dark.
