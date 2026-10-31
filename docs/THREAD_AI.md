# Wątki odpowiedzi i Intelligence kanału: notatki

Gałąź `claude/thread-ai-0a2162`, 31.10.2026. Cztery commity, po jednym na zmianę, plus ten z dokumentacją.

## Co się zmieniło

### 1. Intelligence kanału w menu po przytrzymaniu
- Zniknął przycisk ✨ z paska narzędzi czatu (`ChannelIntelligenceMenu`).
- Akcje kanału (podsumowanie ostatnich 100/500/1000 wiadomości, Ask About This Channel, Index Channel) są teraz w podmenu **Intelligence** w menu kanału po przytrzymaniu (`PlaceContextMenus.swift`, `ChannelContextMenu`), obok istniejącego Catch Up. Menu ma też własne arkusze Ask i Index.
- W otwartym kanale te same akcje są pod nazwą kanału: tytuł ma strzałkę ▾ i po stuknięciu otwiera menu (Catch Up on Unread, podsumowania, Ask, Index). Działa też w DM-ach, jeśli Intelligence w DM-ach jest włączone w Ustawieniach; bez tego tytuł jest zwykłym tekstem.
- Wspólny widok akcji: `ChannelIntelligenceActions` w `ChannelSummarySheet.swift`.

### 2. Show Thread i Explain Context na całym wątku
- W menu wiadomości, która jest odpowiedzią (nie przekazaniem), jest **Show Thread**.
- `ReplyThreadCollector` (`Aicord/Common/Chat/Messages/ReplyThreadSheet.swift`) idzie po `message_reference` w górę: najpierw z wczytanej historii kanału (`GatewayStore.loadedMessages(in:)`), potem z `referenced_message`, a brakujące pobiera po id przez API, najwyżej 50 w górę. Dokłada wczytane wiadomości, które odpowiadają na którąkolwiek z łańcucha (także pośrednio). Pomija zablokowanych, sortuje od najstarszej.
- Arkusz **Thread**: lista od najstarszej, wiadomość, z której przyszedłeś, podświetlona, przy odpowiedzi na coś innego niż wiersz wyżej dopisek „Replying to …”. Stuknięcie przenosi do wiadomości w kanale.
- Czysta logika w AicordKit (`ReplyThread.laterReplies`, `ReplyThread.fit`) z testami (`ReplyThreadTests`).
- **Explain Context** dostaje cały wątek zamiast 2–3 odpowiedzi: cel, potem to, na co odpowiada, od najbliższego w górę, potem reszta najbliżej celu, w budżecie ok. 1000 tokenów na urządzeniu i 12 000 przez API. W prompcie wątek jest osobną sekcją, przed rankingiem wcześniejszych wiadomości. Show Conversation pokazuje cały wątek.
- **Summarize Replies** (dla odpowiedzi bez wątku Discorda) też czyta cały wątek.

### 3. Wyniki Intelligence zostają na czas sesji
- `MessageIntelligenceCache`: gotowa odpowiedź (punkty, transkrypt, rozmowa, wyszukiwania, notka) per wiadomość i akcja, w pamięci do zamknięcia aplikacji.
- Ponowne otwarcie pokazuje ją od razu z dopiskiem „From earlier in this session…”; przycisk ↻ **Regenerate** w pasku liczy od nowa.

### Ostrzeżenie
- `IntelligenceTools.swift:412`: zbędne `await` przed `toolbox.maxCalls` (stała `let`) usunięte.

Nowe napisy mają polskie tłumaczenia w `Localizable.xcstrings`. Starsze napisy Intelligence nadal nie są przetłumaczone (tak było już wcześniej).

## Co sprawdziłem
- Build iOS (symulator) i macOS przechodzą, ostrzeżenia z linii 412 już nie ma; `swift test` w AicordKit: 152 testy, 0 błędów.
- Symulator iOS (iPhone 18 Pro), konto użytkownika, zapis tylko na NAScin:
  - przytrzymanie kanału (tylko podgląd, na innym serwerze): podmenu Intelligence z podsumowaniami, Ask i Index;
  - #ogólny na NAScin: brak przycisku ✨, menu pod nazwą kanału z pełną listą akcji;
  - wysłałem na NAScin trzy wiadomości testowe „Thread test 1/2/3” (2 odpowiada na 1, 3 na 2). Show Thread nie pojawia się przy wiadomości, która nie jest odpowiedzią; na „Thread test 2” pokazuje 1, 2 (podświetlona) i późniejszą 3; stuknięcie przenosi do wiadomości;
  - Explain Context na „Thread test 3” z modelem na urządzeniu: odpowiedź cytuje wiadomość z wątku, Show Conversation ma 3 wiadomości;
  - po przejściu do cytowanej wiadomości i ponownym otwarciu Explain Context wynik jest od razu, z dopiskiem o sesji; Regenerate liczy od nowa i dopisek znika.

## Czego nie sprawdziłem
- Długiego wątku (ponad 50 wiadomości, rodzice spoza wczytanej historii pobierani po id) ani przycinania do budżetu w praktyce: tylko testy jednostkowe.
- Explain Context z modelem przez API (na NAScin można, nie było potrzeby przy krótkim wątku).
- Niczego na Macu poza buildem: menu pod nazwą kanału jest w pasku `.navigation`, podmenu w menu kanału po prawym kliknięciu.
- Uwaga z testów: po skoku do wiadomości, gdy pole tekstowe miało fokus (klawiatura systemowa ukryta w symulatorze), czat zostaje w układzie „z klawiaturą” i wiadomość ląduje za polem tekstowym. To zachowanie istniejącego skoku (`ChannelStore.jump` + `ignoresSafeArea(.keyboard)`), nie tej zmiany; po ponownym uruchomieniu działa normalnie.
