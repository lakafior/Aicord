# Zaproszenia, znajomi i karty wideo (Etap 8, pkt 8): notatki

Gałąź `claude/invites-pack-7779cd`, trzy commity:

- `b281a48` feat(lib): modele linków zaproszeń, czasu ważności, limitu użyć i błędów zaproszeń do znajomych (+5 testów, razem 110)
- `dc53caa` feat: karty wideo, Add Friend, Invite People, podgląd zaproszeń
- `b871e55` feat: rozszerzenie Safari

Buildy iOS (symulator) i macOS przechodzą. `swift test` w `AicordKit`: 110 testów, 0 błędów.

## Co jest zrobione

### 1. Karty embedów `video` (YouTube i inne)
- `Embeds/VideoEmbedView.swift`: karta z paskiem w kolorze embedu, nazwą dostawcy, autorem (link do kanału), tytułem (link) i miniaturą z przyciskiem odtwarzania. Opis tylko poza YouTube (Discord też go tam nie pokazuje), maksymalnie 3 linie.
- Stuknięcie: jeśli Discord proxuje plik wideo (`video.proxy_url`), film gra w przeglądarce załączników. W przeciwnym razie (YouTube, Vimeo, Twitch) otwiera się link przez `openURL`. Na iOS uniwersalny link otwiera aplikację YouTube, jeśli jest zainstalowana, a jeśli nie, Safari.
- Ustawienia: „Show Link Previews” wyłączone ukrywa wszystkie embedy, jak dotąd. „Show Media from Links” wyłączone **zostawia kartę wideo z tytułem, ale bez miniatury**. Wcześniej embedy `video` znikały całkiem; Discord przy tym ustawieniu też zostawia tekst. Embedy wideo bez tytułu (gołe linki do mp4) przy wyłączonym ustawieniu nadal znikają.
- Wrażliwe media: bez zmian, embed z flagą explicit/gore przechodzi przez istniejące `MediaFilter` i `SensitiveMediaCover`.
- Inne typy, które dawały „Unsupported embed type”: `poll_result` (karta „poll ended”: pytanie, zwycięska odpowiedź, głosy), `auto_moderation_message` (karta AutoMod: treść, reguła, słowo kluczowe) oraz przyszłe `__undocumented` (pokazywane jak `rich`, jeśli mają tytuł, opis lub pola; inaczej nic). Napisu „Unsupported embed type” już nie ma (klucz w `Localizable.xcstrings` zostanie oznaczony jako stale przy następnej synchronizacji katalogu).

### 2. Add Friend
- `Profiles/AddFriend.swift`: arkusz `AddFriendSheet` z polem na nazwę (akceptuje też `@nazwa` i stare `nazwa#1234`) i `AddFriendProfileButton`.
- Wejście: wiersz „Add Friend” na górze Messages → Friends (`FriendsSheet`, iOS i macOS). **Decyzja:** wiersz zamiast przycisku w pasku narzędzi, bo na iOS 26 drugi przycisk w pasku obok „Done” był chowany albo pojawiał się z opóźnieniem.
- Komunikaty błędów są po angielsku, jak reszta UI. Sprawdzane lokalnie przed wysyłką: niepoprawna nazwa (2–32 znaki, `a-z0-9_.`), własna nazwa, już znajomi, zaproszenie już wysłane, zaproszenie przychodzące od tej osoby, zablokowany. Z kodów Discorda: 80004 brak osoby, 80007 już znajomi, 80000 nie przyjmuje zaproszeń, 80001 zablokowane, 80002 bot, 80003 Ty, 30002 limit 1000 znajomych, 40002 konto niezweryfikowane, 429 za szybko. Pozostałe pokazują komunikat Discorda.
- Profil: w popoucie (`ProfilePopoutView`) i panelu profilu w DM (`DMProfilePanel`) przycisk „Add Friend”, „Accept Friend Request” albo napis „Friend Request Sent”, zależnie od relacji. Nie pokazuje się dla siebie, botów, znajomych i zablokowanych. Używa `createRelationship` bez typu, co wysyła zaproszenie albo przyjmuje przychodzące.
- **Uwaga do równoległej pracy:** `DMProfilePanel.swift` leży w `Member Sidebar`. Dopisałem tam jedną linię (`AddFriendProfileButton(user: user)` pod bio). Przy scalaniu z gałęzią list może być drobny konflikt.

### 3. Invite People
- `Guilds/InvitePeopleSheet.swift`: `InvitePeopleView` (formularz) i `InvitePeopleSheet` (arkusz z „Done”).
- Wejście: „Invite People” w menu serwera (`PlaceContextMenus.swift`, pod „Pin to Top”) i wiersz na górze Server Settings (NavigationLink).
- Kanał domyślny: bieżący, jeśli serwer jest otwarty i wolno zapraszać do tego kanału; w przeciwnym razie pierwszy kanał tekstowy (po `position`) z uprawnieniami View Channel i Create Instant Invite. Wybieralne są kanały tekstowe, ogłoszeń, głosowe, stage, fora i media.
- Bez uprawnienia do żadnego kanału opcja w menu i w ustawieniach jest wyłączona, a sam widok pokazuje „Can't Invite”. Gdy uprawnień nie da się jeszcze policzyć (sklep serwera nie załadowany), opcja jest włączona, a ewentualny błąd 50013 pokazuje czytelny komunikat.
- Czas ważności: 30 min, 1 h, 6 h, 12 h, 1 dzień, 7 dni (domyślnie, jak Discord), nigdy. Limit użyć: brak, 1, 5, 10, 25, 50, 100.
- **Decyzja:** link tworzy się od razu po otwarciu i po każdej zmianie ustawień, z `unique: false`. Discord oddaje wtedy istniejący link o tych samych ustawieniach, więc przełączanie w tę i z powrotem nie mnoży zaproszeń. Wynik: przycisk „Copy Link” (z potwierdzeniem „Copied”) i `ShareLink`.

### 4. Join (podgląd zaproszenia)
- `Guilds/InvitePreview.swift`: `InviteCache` (jedno `resolveInvite` z licznikami na kod na uruchomienie), `InvitePreview` (karta albo układ arkusza) i `InvitePreviewSheet`.
- Karta w czacie: pod treścią wiadomości (`MessageBody.swift`), do 3 kart na wiadomość, dla każdego linku `discord.gg/…`, `discord.com/invite/…` i `discordapp.com/invite/…` w tekście. Karta pokazuje ikonę (albo inicjały), nazwę, liczbę osób online i członków oraz przycisk **Join**; gdy już jesteś członkiem, **Open**. Przy wygasłym albo błędnym kodzie: „Invalid Invite”. Obsługuje też zaproszenia do group DM i friend invites.
- **Uwaga:** opis zadania wskazywał „Invite-Only Server” w `MarkdownText.swift`. To napis w popoverze emoji (serwer, z którego pochodzi emoji), a nie karta zaproszenia; kart zaproszeń wcześniej nie było. Zrobiłem je od zera pod wiadomością, a popover emoji zostawiłem bez zmian.
- Join: `acceptInvite`. Captcha przechodzi przez istniejący `captchaCallback` klienta (arkusz `CaptchaSheet` i ponowienie). Po sukcesie karta czeka do 10 s, aż serwer przyjdzie przez gateway, i otwiera go na kanale z zaproszenia. Błędy: limit serwerów, ban, nieważne zaproszenie, inne z komunikatem Discorda.
- Otwarcie linku: stuknięcie linku zaproszenia w treści (akcja `openURL` w `MarkdownText`) i link `aicord://invite/KOD` (`onOpenURL` w `RootView`) ustawiają `appState.invitePreviewCode`, a `AicordSheetsAlerts` pokazuje arkusz. Na macOS link trafia do otwartego okna (`handlesExternalEvents`).
- Schemat URL: dodany `aicord` w `Info.plist` (`CFBundleURLTypes`). **Decyzja:** nowy schemat zamiast `paicord`. `paicord://` jest używany wewnętrznie tylko w atrybutach tekstu i nie był zarejestrowany; zarejestrowanie go mogłoby kolidować z oryginalnym Paicordem zainstalowanym obok.

### 5. Rozszerzenie Safari
- Nowy target `AicordSafari` (Safari Web Extension, `com.apple.product-type.app-extension`), bundle `net.smigi.aicord.SafariExtension`, iOS i macOS w jednym targecie (`SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`). Osadzony w aplikacji przez fazę „Embed Foundation Extensions”. Zależność i osadzanie mają `platformFilters = (ios, macos)`, żeby nie psuć buildu visionOS aplikacji.
- Pliki: `AicordSafari/SafariWebExtensionHandler.swift` (pusty handler), `Info.plist` (`NSExtension`), `Resources/manifest.json` (MV3), `content.js`, `_locales/en/messages.json`, ikony 48/96/128 z ikony aplikacji.
- Działanie: content script na `discord.gg/*` i `discord.com|discordapp.com/invite/*` (z subdomenami) uruchamia się na `document_start` i przekierowuje na `aicord://invite/KOD`. Zapamiętuje kod w `sessionStorage`, więc powrót do strony nie odbija drugi raz (można zostać na stronie). Rozszerzenie nie ma uprawnień poza dostępem do tych stron, który użytkownik przyznaje w Safari.
- **AltStore (Etap 12):** przy instalacji z darmowym kontem Apple ID rozszerzenie zajmuje **drugi z 3 dostępnych App ID** (aplikacja + rozszerzenie), a każde App ID trzeba odnawiać co 7 dni razem z aplikacją. Jeśli to przeszkadza, rozszerzenie można wyrzucić z wersji AltStore (osobny schemat albo usunięcie z fazy osadzania).

## Testy, które zrobiłem

Uwaga: przez część sesji druga sesja (listy) instalowała swój build na tym samym symulatorze, więc wyniki z iOS sprzed ~21:20 nie są wiarygodne. Większość testów zrobiłem na macOS (build z tej gałęzi), a końcowe na iOS po potwierdzeniu, że zainstalowany build jest mój (zgodna data i rozmiar `Aicord.debug.dylib`).

| Co | Gdzie | Wynik |
|---|---|---|
| Karta YouTube (`youtu.be/6PQdjee-YuA`, FashionReps Polska → #guides) | iOS | Karta: YouTube, Ducksly, tytuł, miniatura z ▶. Stuknięcie otwiera YouTube w Safari (w symulatorze nie ma aplikacji YouTube). |
| Invite People z menu serwera NAScin | macOS | Link `discord.gg/EdxGVcWd` (#ogólny, 7 dni, bez limitu). Zmiana na 30 min dała nowy link `ZZ79tpx`. Copy Link skopiował URL do schowka. |
| Podgląd przez `aicord://invite/ZZ79tpx` | macOS i iOS | Arkusz: „N”, NAScin, 2 Online, 2 Members, przycisk **Open** (jesteś członkiem). Open zamyka arkusz i przechodzi na serwer. Na iOS najpierw systemowe „Open in Aicord?”. |
| Karta zaproszenia w czacie | macOS | Wysłana wiadomość w NAScin #ogólny: „Test karty zaproszenia: https://discord.gg/ZZ79tpx” → karta NAScin z **Open**. |
| Add Friend: nieistniejąca nazwa | macOS | „Nobody goes by that username…” (kod 80004). |
| Add Friend: za długa nazwa | iOS | Komunikat o niepoprawnej nazwie (po poprawce; wcześniej był surowy `ValidationError`). |
| Add Friend: `daoy7l6jf8` (Twoje konto testowe) | macOS | **Discord zwrócił 80004 (nie ma takiej osoby)**, więc zaproszenie nie poszło (zakładka Sent pusta). Możliwe przyczyny: Discord nie pozwala znaleźć konta bez weryfikacji telefonu albo nazwa użytkownika różni się od wyświetlanej. |

## Do sprawdzenia przez Ciebie

1. **Add Friend naprawdę:** Messages → Friends → Add Friend, wpisz dokładną nazwę użytkownika (Settings → My Account na koncie testowym, nie display name) → Send Friend Request. Oczekiwane: zielone „Friend request sent to …”, osoba pojawia się w Sent. Jeśli dalej 80004, to ograniczenie Discorda dla niezweryfikowanych kont.
2. **Add Friend w profilu:** otwórz profil kogoś, kto nie jest znajomym (popout z wiadomości na serwerze albo panel profilu w DM) → „Add Friend”. Po wysłaniu powinno zmienić się na „Friend Request Sent”. Tego nie testowałem.
3. **Join:** potrzebny serwer, w którym nie jesteś (np. konto testowe zaprasza Cię na swój serwer, albo zaproszenie z innego konta na NAScin otwarte na koncie testowym). Kliknij Join na karcie. Oczekiwane: dołączenie i przejście na kanał z zaproszenia; jeśli Discord poprosi o captchę, pojawi się arkusz captchy i potem ponowienie. Tego nie testowałem, bo nie wolno mi było dołączać do innych serwerów.
4. **Rozszerzenie Safari:**
   - iOS: Ustawienia → Aplikacje → Safari → Rozszerzenia → „Aicord Invites” → włącz i zezwól na discord.com / discord.gg. Otwórz w Safari `https://discord.gg/<kod>` → „Otworzyć w Aicord?” → podgląd zaproszenia.
   - macOS: uruchom Aicord raz, potem Safari → Ustawienia → Rozszerzenia → „Aicord Invites” → włącz, daj dostęp do discord.com i discord.gg. Build deweloperski może wymagać Develop → „Allow Unsigned Extensions”. Rozszerzenie jest zarejestrowane w systemie (`pluginkit` je widzi), ale **nie włączałem go w Safari** (to Twoja przeglądarka, a w Ustawieniach symulatora nie dało się wiarygodnie wpisywać). Przekazanie linku `aicord://invite/…` do aplikacji przetestowałem na obu systemach.
5. **Karta wideo przy „Show Media from Links” wyłączonym:** karta YouTube powinna zostać bez miniatury.

## Pozostałości po testach (NAScin)
- Zaproszenia: `discord.gg/EdxGVcWd` (7 dni, wygaśnie ok. 6 listopada) i `discord.gg/ZZ79tpx` (30 min, już wygasło). **Nie usunąłem ich:** aplikacja nie ma UI do `revokeInvite`, a nie chciałem wysyłać zapytań z tokenem poza aplikacją. Usuń `EdxGVcWd` w Server Settings → Invites w oficjalnym kliencie albo poczekaj, aż wygaśnie.
- Wiadomość testowa w NAScin #ogólny: „Test karty zaproszenia: https://discord.gg/ZZ79tpx” (21:19).

## Ryzyka i znane problemy
- **Stuknięcie linku zaproszenia w treści wiadomości na macOS** nie otwierało podglądu w moich testach. Za pierwszym razem otworzyło stronę w przeglądarce, potem kliknięcia nie docierały do `NSTextInteractionView` z Textual (log diagnostyczny w akcji `openURL` się nie pojawił). Karta pod wiadomością i `aicord://` działają. Wygląda to na kwestię obsługi myszy w Textual (lub mojego wstrzykiwania kliknięć), a nie na tę zmianę; wcześniej takie linki też nic nie robiły. Warto kliknąć ręcznie.
- `project.pbxproj`: nowe pliki i target dodane ręcznie (skryptem); buildy przechodzą, ale przy pierwszym otwarciu w Xcode może przepisać kolejność wpisów. Podpisywanie rozszerzenia: Automatic, zespół 5TA8RF548P jak aplikacja. Dla AltStore trzeba sprawdzić, czy przepisuje ono też bundle ID rozszerzenia.
- `InviteCache` trzyma wyniki do końca działania aplikacji. Licznik członków nie odświeża się, a wygasłe w międzyczasie zaproszenie dalej wygląda na ważne aż do kliknięcia Join (wtedy błąd „invalid or expired”).
- Join czeka maksymalnie 10 s na `GUILD_CREATE`; przy wolnym gatewayu nie przełączy na serwer, choć dołączenie się udało.
- Teksty UI są po angielsku i trafią do `Localizable.xcstrings` przy następnej ekstrakcji (build z Xcode); tłumaczeń nie dodawałem.

## Proponowane wpisy do dokumentacji

### ROADMAP (Etap 8, pkt 8 „Poprawki interfejsu”): do odhaczenia
- [x] Karty YouTube i innych embedów `video`
- [x] Add Friend (lista znajomych i profil)
- [x] Invite People (menu serwera i Server Settings)
- [x] Join: karta zaproszenia i otwieranie linków zaproszeń
- [x] Rozszerzenie Safari otwierające zaproszenia w Aicord
- Nowy punkt do rozważenia: lista i unieważnianie zaproszeń serwera (Server Settings → Invites, `revokeInvite`).

### SHIPPED.md (EN)
- YouTube and other video links show a card with the channel, title and a thumbnail with a play button; tapping opens the video in its app or the browser. Poll results and AutoMod alerts get cards too, so no more “Unsupported embed type”.
- Add Friend by username from Messages → Friends, with clear errors, and from people's profiles.
- Invite People from the server menu and Server Settings: pick the channel, expiry and use limit, then copy or share the link.
- Server invite links in chat show the server with a Join button, or Open if you're already in it. Tapped invite links open the same preview.
- A Safari extension (iOS and macOS) opens discord.gg and discord.com/invite links in Aicord instead of the website.
