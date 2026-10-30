# Voice — notatki z realizacji Etapu 9

Gałąź `claude/voice-b61e94`. Praca autonomiczna, 30.10.2026. Ten plik zbiera decyzje,
stan, to, czego nie sprawdzono, oraz instrukcję testu z drugą osobą.

## Stan w skrócie

- PaicordLib buduje się (`swift build`), 102 testy przechodzą, w tym 16 nowych dla voice.
- Aplikacja buduje się na macOS (arm64) i na symulatorze iOS.
- Test na prawdziwym koncie (symulator iOS, tryb listen-only, wyciszony): dołączenie do pustego
  kanału głosowego `dev` na serwerze Eggcord i wyjście, dwa razy. Log z drugiego razu:

  ```
  Connecting to voice server (host=c-waw02-….discord.media)
  Voice state idle → connecting → discovering
  UDP discovery done (mode=aead_aes256_gcm_rtpsize)
  Session description received (dave=1)
  DAVE key package sent (437 B)
  Voice state discovering → negotiatingEncryption
  DAVE external sender received
  … 38 s połączenia, heartbeaty bez problemów …
  Voice state negotiatingEncryption → disconnected(requested)
  ```

  W UI: pasek „Voice Connected” z przekreślonym mikrofonem, ja na liście pod kanałem `dev`
  z ikoną wyciszenia, po rozłączeniu znikam.
- Pełny log z obu prób: `side-session-notes/…/voice-test-log.txt` (bez tokenów i kluczy).

## Architektura

| Warstwa | Gdzie | Co robi |
| --- | --- | --- |
| Modele | `DiscordModels/Types/VoiceGateway*.swift`, `RTP/` | Payloady voice gateway v8, RTP na `Data`, kody zamknięcia z polityką odzyskiwania |
| Transport | `DiscordVoice/VoiceGatewayManager.swift`, `VoiceUDPConnection.swift` | WebSocket na `URLSessionWebSocketTask`, UDP na `NWConnection`, maszyna stanów, limity czasu |
| Szyfrowanie | `DiscordVoice/TransportCipher.swift` | `aead_aes256_gcm_rtpsize`, `aead_xchacha20_poly1305_rtpsize` (własne HChaCha20) na CryptoKit |
| DAVE | `DiscordVoice/DaveSession.swift` | Protokół DAVE na C API libdave z DaveKit, budżety i zabezpieczenia |
| Kodek i odbiór | `DiscordVoice/OpusCodec.swift`, `JitterBuffer.swift` | Opus (libopus ze `swift-opus`), jitter buffer i PLC z Serein, mikser |
| Audio | `Paicord/Utilities/Audio/` | `AVAudioEngine` z voice processing, VAD, push-to-talk, urządzenia, preferencje |
| Logika rozmowy | `Paicord/Stores/VoiceConnectionStore.swift` | Dołączanie przez op 4, czekanie na serwer głosu, wyciszenie, wyłączenie dźwięku, dzwonienie w DM |
| UI | `Paicord/Common/Voice/`, `Settings/VoiceVideo/` | Pasek rozmowy, wiersz kanału głosowego z uczestnikami, przycisk połączenia w DM, ustawienia |

## Decyzje

1. **C++ interop nie zostaje w `DiscordVoice` sam z siebie.** Sprawdzone: z `internal import DaveKit`
   PaicordLib wywraca się na skanowaniu modułu `CLibdave` (nagłówki C++), a z `@_implementationOnly`
   dostaje „module 'DiscordVoice' was built with C++ interoperability enabled”. Rozwiązanie:
   - `DaveKit` importowany `@_implementationOnly` (z `CheckImplementationOnly`, więc kompilator
     pilnuje, żeby typy DaveKit nie wyciekły do publicznego API);
   - targety, które importują `DiscordVoice` (PaicordLib, TestCode, DiscordBMTests) i aplikacja
     dostają `-Xfrontend -disable-cxx-interop-requirement-at-import` (w `Package.swift` jako
     `unsafeFlags`, w projekcie jako `OTHER_SWIFT_FLAGS`).
   Reszta targetów zostaje w zwykłym Swift 6 bez C++. `unsafeFlags` działają, bo PaicordLib jest
   lokalnym pakietem; gdyby kiedyś był zależnością zdalną, trzeba to przemyśleć.
   Testy nie mogą używać `@testable import DiscordVoice` (to przeciąga DaveKit), więc testowane typy
   są `package`.
2. **Własna warstwa DAVE zamiast `DaveSessionManager` z DaveKit.** Używamy C API libdave, które DaveKit
   kompiluje i reeksportuje. Powody: `DaveSessionManager` zapisuje ID przejścia tam, gdzie powinna być
   wersja protokołu (`lastPreparedTransitionVersion = transitionId`), nie zwalnia bufora z
   `daveSessionProcessProposals` i nie ma budżetów. DaveKit przypięty do commitu `a4c4e18`.
3. **Zabezpieczenia DAVE.** libdave sam sprawdza ID grupy commitu, nadawcę propozycji (tylko external
   sender), typy propozycji (tylko Add/Remove) i to, czy dodawany użytkownik jest na liście
   rozpoznanych. My dokładamy: listę rozpoznanych tylko z opcode 11 (uwierzytelnieni przez serwer
   głosu), w rozmowie 1:1 tylko rozmówca, maks. 64 uczestników, propozycje przed powstaniem grupy są
   ignorowane, odmowa wyłączenia E2EE w trakcie rozmowy (downgrade), 3 próby odtworzenia nieprawidłowej
   grupy, 1024 przejścia. Żadnych mediów, dopóki enkoder nie ma klucza bieżącej epoki. Logi libdave
   tylko na poziomie warning/error, nasze logi DAVE podają tylko rozmiary.
4. **Opus przez `Copus` + mały shim w C.** `opus_encoder_ctl` jest wariadyczne i Swift go nie widzi,
   a wrapper `Opus` ze `swift-opus` nie daje bitrate, FEC ani PLC. `COpusShim` to sześć funkcji.
   Mikrofon idzie mono 64 kbit/s z FEC, odbiór dekodowany do mono — jak w Serein.
5. **Opus, jitter buffer i mikser w PaicordLib, nie w aplikacji.** Dzięki temu aplikacja nie potrzebuje
   nowych pakietów w `project.pbxproj` (dalej tylko PaicordLib i Textual), a jitter buffer ma testy.
   Aplikacja dostaje gotowe ramki 20 ms do odtworzenia.
6. **Jitter buffer przeniesiony 1:1 z Serein** (`jitter.rs`, MIT/Apache) razem z testami.
7. **XChaCha20 na CryptoKit.** CryptoKit ma tylko ChaChaPoly z 12-bajtowym nonce; XChaCha to
   HChaCha20 (własna implementacja, 20 rund) plus ChaChaPoly z podkluczem. Gałąź voice podawała
   24-bajtowy nonce do `ChaChaPoly`, co nie mogło działać. Wektory testowe wygenerowane niezależnie
   przez OpenSSL (Python `cryptography`), HChaCha20 sprawdzone też wektorem z draftu IETF.
8. **Nonce transportu to własny licznik**, nie numer sekwencji RTP, i kończy sesję przy wyczerpaniu.
9. **Poprawki modeli z gałęzi voice:** JSON v8 ma klucz `seq` (nie `s`), pola Ready i Session Description
   mogą nie przyjść, port w odpowiedzi IP discovery jest big-endian (gałąź czytała little-endian).
10. **Rozłączenia jak w Serein.** Utrata sesji głównego gatewaya (nowe Ready), sesja głosu, której nie da
    się wznowić, albo nasza sesja na innym urządzeniu kończy rozmowę lokalnie; ponowne dołączenie to
    świadoma akcja. Kody 4014/4022 = usunięto z kanału, 4006/4009/4011 = sesja nieważna, 4015 = resume.
11. **Sam w kanale = „połączono”.** Gdy nikogo nie ma, grupa DAVE nie powstaje i nic nie wychodzi, ale
    UI pokazuje „Voice Connected”, a rozmowa w DM dzwoni właśnie w tym momencie.
12. **Push-to-talk tylko przy aktywnej aplikacji** (lokalny monitor zdarzeń na macOS, przycisk do
    przytrzymania w panelu). Globalny skrót wymagałby uprawnienia Input Monitoring. Klawisze znakowe
    nie działają, gdy fokus jest w polu tekstowym.
13. **Urządzenia:** na macOS lista z Core Audio i wybór przez `kAudioOutputUnitProperty_CurrentDevice`;
    na iOS tylko wejście (`setPreferredInput`), wyjście wybiera system.
14. **Tryb listen-only do testów:** `-Paicord.Voice.ListenOnly YES` przy uruchomieniu — mikrofon się nie
    otwiera, aplikacja nie prosi o dostęp, rozmowa jest wyciszona bez zmiany zapisanego ustawienia.
15. **Entitlement mikrofonu na macOS** (`ENABLE_RESOURCE_ACCESS_AUDIO_INPUT = YES`), tryb tła `audio`
    na iOS, opis użycia mikrofonu wspomina rozmowy.
16. **Endpointy rozmów w DM** (`getCallEligibility`, `modifyCall`, `ringChannelRecipients`,
    `stopRingingChannelRecipients`) przeniesione z gałęzi voice.

## Czego nie sprawdzono

- **Dźwięku w ogóle.** Nikogo nie było w kanale, więc grupa DAVE nie powstała, nie wyszedł ani nie
  przyszedł żaden pakiet z dźwiękiem. Nie sprawdzono więc: commit/welcome i przejść DAVE na żywo,
  szyfrowania i odszyfrowania ramek przez libdave, odtwarzania, VAD, push-to-talk w praktyce.
- **macOS na żywo.** Aplikacja uruchomiona z mojej powłoki nie otwiera okna (ograniczenie sandboksa),
  więc na Macu sprawdzono tylko build. UI na macOS (pasek nad `ProfileBar`, skróty ⌘⇧M i ⌘⇧D,
  push-to-talk z klawisza, wybór urządzeń z Core Audio) jest niesprawdzony.
- **Rozmowy w DM i grupowe** — z założenia nie dzwoniłem do nikogo.
- **Wznowienia po zerwaniu sieci** (resume) i kodów zamknięcia na żywo.
- **Tryb `aead_xchacha20_poly1305_rtpsize` na żywo** — serwer wybrał AES-GCM; XChaCha ma tylko testy.
- **Wybór urządzenia na macOS przy włączonym voice processing** — Apple nie dokumentuje dobrze, czy
  ustawienie urządzenia na węźle VPIO zawsze działa.

## Ryzyka

- `-disable-cxx-interop-requirement-at-import` to flaga frontendu, nie oficjalne API; może zniknąć
  albo zmienić znaczenie w nowym Swifcie. Alternatywą jest C++ interop w całej aplikacji (jak na
  gałęzi voice).
- `@_implementationOnly` bez library evolution jest dopuszczone dzięki `CheckImplementationOnly`, ale
  to funkcja eksperymentalna.
- DaveKit ciągnie binarny `OpenSSL.xcframework` (krzyzanowskim/OpenSSL). W sandboksie SwiftPM nie
  potrafił go pobrać do `~/Library/Caches`; pobrałem plik ręcznie do cache w scratchpadzie. U Ciebie
  w Xcode powinno pobrać się normalnie.
- Dzwonienie w DM dzwoni zawsze przy starcie rozmowy, także gdy ktoś już jest w rozmowie (gałąź voice
  robiła tak samo). Serein nie dzwoni przy dołączaniu do trwającej rozmowy — do poprawy, gdy aplikacja
  zacznie śledzić `CALL_CREATE`.
- Brak banera „rozmowa trwa” / odbierania i odrzucania połączeń przychodzących — to nie było w zakresie
  punktów 1–6, ale bez tego odebranie rozmowy wymaga wejścia w DM i kliknięcia słuchawki.

## Test z drugą osobą (do zrobienia przez Ciebie)

Potrzebne: druga osoba z oficjalnym klientem Discorda, słuchawki po obu stronach (bez nich echo
utrudni ocenę), Aicord z tej gałęzi na Macu albo iPhonie. Logi: na Macu uruchom z terminala
`…/Paicord.app/Contents/MacOS/Paicord 2>&1 | grep -E "VoiceGateway|libdave|Voice"` albo podejrzyj
konsolę Xcode; wpisy `info` pokazują każdy krok.

1. **Kanał serwera, dwie osoby.**
   - Druga osoba wchodzi pierwsza na pusty kanał głosowy wspólnego serwera.
   - W Aicord kliknij ten kanał. W logu powinno być: `Session description received (dave=1)`,
     `Participants joined count=1`, `DAVE key package sent`, `DAVE external sender received`, potem
     `DAVE proposals received` albo `DAVE welcome received`, `DAVE ready for transition`,
     `DAVE transition executed` i `Voice media ready`. Pasek pokaże kłódkę.
   - Mów na zmianę: druga osoba ma Cię słyszeć, Ty ją; zielone obwódki przy mówiącym.
   - Wycisz (przycisk lub ⌘⇧M): druga osoba widzi przekreślony mikrofon i nic nie słyszy.
   - Wyłącz dźwięk (⌘⇧D): nic nie słyszysz, druga osoba widzi przekreślony głośnik.
2. **Dołączanie i wychodzenie.** Niech druga osoba wyjdzie i wróci. W logu `Participants joined`,
   nowe przejście DAVE, dźwięk wraca w obie strony bez ponownego łączenia z Twojej strony.
3. **Trzecia osoba (rozmowa grupowa na kanale).** Dołącza trzecia osoba — wszyscy słyszą wszystkich.
4. **Push-to-talk.** Settings → Voice & Video → Input Mode: Push to Talk. Na Macu trzymaj ` (lub inny
   wybrany klawisz) przy aktywnym oknie Aicord, na iPhonie przytrzymaj przycisk z falami w panelu.
   Dźwięk ma iść tylko w trakcie trzymania (plus opóźnienie zwolnienia).
5. **DM.** Otwórz DM z drugą osobą, kliknij słuchawkę w nagłówku. U niej powinien zadzwonić Discord;
   po odebraniu sprawdź dźwięk jak w punkcie 1. Potem rozmowa grupowa w DM grupowym.
6. **Zerwanie sieci.** W trakcie rozmowy wyłącz Wi-Fi na ~5 s i włącz z powrotem. Oczekiwane:
   `Voice socket closed` → `Voice state … → resuming` → `Voice session resumed` i dźwięk wraca. Przy
   dłuższej przerwie główny gateway się przełączy i rozmowa skończy się komunikatem — to zamierzone.
7. **Urządzenia.** Na Macu zmień wejście/wyjście w Settings → Voice & Video, wyjdź i wejdź ponownie
   (zmiana działa od następnego dołączenia).

Jeśli coś nie działa, najważniejsze w logu są linie `DAVE …`, `Voice deadline passed` i
`Voice connection ending`.
