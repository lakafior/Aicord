# Polski, onboarding i zarządzanie serwerem (1.11.2026)

Trzy zadania, trzy commity na gałęzi `claude/pl-onboarding-admin-9238c1`. Testy w symulatorze iPhone 18 Pro (iOS 27), po polsku (`-AppleLanguages (pl)`). Zrzuty ekranu leżą w notatkach grupy sesji: `side-session-notes/…/pl-onboarding-shots/`.

Nie wchodziłem do zakładki Wiadomości ani DM-ów i nikogo nie zapraszałem. Wszystko, co zapisuje, robiłem tylko na własnym serwerze „Aicord Test”.

## 1. Tłumaczenia

- Brakowało 507 wpisów (z 1298). Pierwsze tłumaczenie zrobił model pomocniczy (Mistral) na podstawie istniejących tłumaczeń jako słownika. Całość przejrzałem i ok. 110 wpisów poprawiłem ręcznie: rodzaj („dodał/a” jak w istniejących), terminy (ghost ping, timeout, Nitro, Stage zostają), błędne liczby i kalki.
- Liczby: zamiast `^[…](inflect: true)` są warianty liczby mnogiej w katalogu (one/few/many/other). Gdzie zdanie zawiera dwie liczby, odmiana idzie przez `substitutions` (np. „%lld głosy z %lld”). Kilka zdań z liczbą przeredagowałem na „Etykieta: %lld”, żeby żadna forma nie była błędna (np. „Pominięte ukryte wiadomości: 3.”).
- Przy okazji odmiana dla starszych napisów: „%lld members” (1 członek, 5 członków) i „Last %lld Messages” (wcześniej zawijało się w menu jako „Ostatnie wiadomo-ści: 100”).
- Sprawdzone w symulatorze: lista serwerów i członków, Kanały i role, regulamin, Ustawienia → Powiadomienia i Alerty. Poprawione po obejrzeniu: ucięty tytuł „Słowa kluczowe i wzor…” → „Słowa i wzorce”, „Osoby do obserwowania” → „Obserwowane osoby”, „Nadrabianie” w menu serwera → „Nadrób zaległości”.
- Ręcznie dodane klucze nie mogą mieć `extractionState: manual`: Xcode generuje dla nich symbole i „Ban” koliduje z „Ban…”. Nowe wpisy mają tylko tłumaczenie, a stan ustawi Xcode przy wyciąganiu napisów.

## 2. Channels & Roles i regulamin

- Przed: wiersze nad kanałami miały nieprzezroczystą komórkę listy z separatorem (`01-before-row-light.png`), arkusz był zwykłą listą (`02-before-sheet-light.png`).
- Po: wiersze jak kanały, z ikoną w zaokrąglonym kafelku i strzałką (`03-after-row-light.png`). Opcje onboardingu to zaokrąglone karty w siatce (na Macu i iPadzie w kilku kolumnach) z emoji w kafelku, opisem i wyraźnym zaznaczeniem: obramowanie i tło w kolorze akcentu (`04-after-sheet-light.png`). Regulamin to numerowana karta z kartą zgody pod nią (`05-after-rules-light.png`). Przycisk akcji jest na dole jako `glassProminent` w `safeAreaInset`. Gdy brakuje wymaganej odpowiedzi, nad przyciskiem pojawia się podpowiedź.
- Kolory: tło `systemGroupedBackground` i karty `secondarySystemGroupedBackground` na iOS, `fill.tertiary` na Macu, czyli kolory systemowe, które same dostosowują się do trybu jasnego i ciemnego. **Trybu ciemnego nie obejrzałem**: motyw aplikacji w symulatorze zostawał jasny mimo ciemnego wyglądu systemu i zmiany motywu na „Auto” (wróciłem do poprzedniej wartości).
- Sprawdzone na LimeWire, Polish Debrid Community i FashionReps Polska, tylko w podglądzie, bez zapisu. Regulamin pokazałem tymczasowo na serwerze, na którym nie mam nic do zaakceptowania (zmiana cofnięta przed commitem), zaznaczyłem zgodę i zamknąłem bez wysyłania.

## 3. Zarządzanie serwerem

Kod: `Aicord/Common/Guilds/Admin/` (`ServerAdmin.swift`: kanały, role, bany, dziennik; `ServerModeration.swift`: akcje na członkach; `CreateServerSheet.swift`). W `AicordKit`: endpoint `listGuildAuditLogEntries`, model `GuildAuditLog`, `removeGuildMemberTimeout` (jawne `null`, bo zwykły payload pomija `nil`), a `unbanUserFromGuild` wysyła teraz powód.

Widoczność:
- Sekcja „Zarządzanie serwerem” w ustawieniach serwera pokazuje tylko części, do których masz uprawnienie (kanały, role, bany, dziennik). Na TRaSH-Guides, gdzie nie mam uprawnień, sekcji nie ma.
- Akcje na członku (`Moderation.actions`) wymagają uprawnienia i wyższej roli niż osoba, na której działasz, chyba że jesteś właścicielem. Nigdy na sobie ani na właścicielu. „Role…” wymaga Manage Roles, a lista pokazuje tylko role poniżej twojej najwyższej.
- „Moderuj” jest w menu wiadomości i w profilu (także otwieranym z listy członków). Na iPhonie profil jest arkuszem, więc z profilu otwiera się własny arkusz, nie ten wspólny dla aplikacji.

Testy na „Aicord Test” (mój serwer, jedyny członek):
- Tworzenie z szablonu: `discord.new/2TffvPucqHkN` (szablon „Blank Server”, którego używa Discord przy „Utwórz własny”) → „Aicord Test” od razu otwarty. Tworzenia od zera osobno nie klikałem; to ten sam arkusz i `POST /guilds`.
- Kanały: utworzony `test-kanal` w kategorii, temat i slowmode 10 s zapisane i widoczne po ponownym otwarciu, usunięty po potwierdzeniu. Utworzony `drugi` i przeciągnięty nad `general`: kolejność zapisała się na serwerze. Tworzenia kategorii nie klikałem.
- Role: utworzona rola, zmieniona na „Tester”, niebieska, pokazywana osobno, bez Manage Channels. Nadana sobie z menu wiadomości (nick zrobił się niebieski) i odebrana z profilu.
- Dziennik audytu: wpisy z autorem, celem i czasem („Utworzono rolę @Tester · Lakafi · 2 minuty temu”). Bany: pusta lista.
- Kick, ban, timeout, zdjęcie timeoutu i unban: **niesprawdzone na żywo**, bo wymagają drugiej osoby. Arkusz bana obejrzałem w wersji tymczasowo pokazującej akcje na sobie (wybór usuwania wiadomości, powód, potwierdzenie `06-ban-sheet-confirm-preview.png`), zamknięty bez wykonania. Ta zmiana nie weszła do commita.
- Do testów wysłałem jedną wiadomość „test” na #general na „Aicord Test”, żeby mieć menu wiadomości i profil.

Serwer „Aicord Test” **został** (kanały `drugi`, `general`, głosowy `General`, rola `Tester`, wiadomość „test”). Aicord nie ma jeszcze usuwania serwera, a przez API z tokenem tego nie robiłem. Usunięcie: w Discordzie, Ustawienia serwera → Usuń serwer.

Znalezione przy okazji: stukanie narzędziem symulatora w przełącznik czasem nie działa (za krótki dotyk). To narzędzie, nie aplikacja: dłuższy dotyk przełącza normalnie. Banery alertów słów kluczowych w symulatorze potrafią przechwycić stuknięcie w górze ekranu i otworzyć inny kanał.

## Zostało

- Kick, ban i timeout z drugim kontem.
- Uprawnienia kanału (nadpisania), kolejność kategorii i ról, pełna lista uprawnień roli, AutoMod, emoji i naklejki, usuwanie serwera (w `ROADMAP.md`, Etap 14 punkt 3).
- Obejrzeć onboarding, regulamin i zarządzanie w trybie ciemnym i na Macu.
