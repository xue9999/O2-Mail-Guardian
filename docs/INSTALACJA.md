# Instalacja krok po kroku

Ta instrukcja jest przeznaczona dla osoby, która nie zajmuje się
programowaniem. Większość instalacji odbywa się w kreatorze.

## Czego potrzebujesz

- Maca z aktualnym systemem macOS;
- połączenia z internetem;
- działającego konta o2.pl;
- prawa do instalowania programów na swoim Macu;
- około 2 GB wolnej pamięci operacyjnej podczas pracy robota i co najmniej
  20 GB wolnego miejsca na dysku.

Pierwsze uruchomienie może potrwać kilkanaście minut, ponieważ pobierane są
lokalne składniki ochrony antyspamowej.

## Krok 1: sprawdź możliwość odzyskania konta

Zanim włączysz logowanie dwustopniowe, zaloguj się do poczty o2 i sprawdź, czy
na koncie jest aktualny numer telefonu lub zapasowy adres e-mail. Zapobiegnie
to utracie dostępu do konta.

## Krok 2: włącz IMAP

Guardian korzysta z IMAP, czyli standardowego, szyfrowanego sposobu dostępu do
folderów pocztowych.

1. Otwórz [pocztę o2](https://poczta.o2.pl/) i zaloguj się.
2. Kliknij **Opcje**.
3. Otwórz kartę **IMAP/POP**.
4. Włącz **IMAP (pobieraj i wysyłaj wiadomości)**.

Nie włączaj POP — nie jest potrzebny. Aktualna instrukcja dostawcy:
[Jak aktywować program pocztowy?](https://pomoc.o2.pl/aktywacja-dostepu-dla-programow-pocztowych).

## Krok 3: włącz logowanie dwustopniowe

1. W poczcie o2 kliknij **Opcje**.
2. W zakładce **Dane i logowanie** znajdź sekcję
   **Logowanie dwustopniowe** i kliknij **Pokaż szczegóły**.
3. Podaj zwykłe hasło do konta.
4. Włącz kod z aplikacji uwierzytelniającej albo klucz bezpieczeństwa.
5. Zapisz wygenerowane klucze awaryjne w bezpiecznym miejscu, innym niż
   skrzynka o2.

Szczegóły i aktualne nazwy ekranów:
[Jak włączyć logowanie dwustopniowe?](https://pomoc.o2.pl/jak-wlaczyc-logowanie-dwustopniowe).

## Krok 4: utwórz hasło tylko dla Guardiana

Po włączeniu 2FA zwykłe hasło do poczty nie powinno być używane w Guardianie.

1. Zaloguj się do ustawień konta o2/WP.
2. Kliknij **Bezpieczeństwo → Logowanie dwustopniowe**.
3. W sekcji **Hasła do programów pocztowych** kliknij **Utwórz hasło**.
4. Jako program wpisz `O2 Mail Guardian`.
5. Jako urządzenie wpisz nazwę swojego Maca, np. `MacBook Air`.
6. Skopiuj wygenerowane hasło bez spacji. Zwykle można je zobaczyć tylko
   podczas tworzenia.

Każdy program i każde urządzenie powinny mieć osobne hasło. W razie problemu
można usunąć tylko hasło Guardiana, nie zmieniając głównego hasła do poczty.
Instrukcja dostawcy:
[Jak utworzyć hasło do programu pocztowego?](https://pomoc.o2.pl/wpkonto/hasla-do-aplikacji-zewnetrznej).

## Krok 5: uruchom `Install.command`

1. Jeżeli pobrałeś `O2-Mail-Guardian-0.3.0.zip`, kliknij go dwukrotnie, a
   następnie otwórz rozpakowany folder **O2 Mail Guardian 0.3.0**. Zobaczysz
   tylko `ZACZNIJ-TUTAJ.txt`, licencję i instalator.
2. Kliknij dwukrotnie **`Install.command`**.
3. Jeżeli pojawi się pytanie macOS, zatwierdź otwarcie.
4. Naciśnij Enter, aby potwierdzić instalację. To jedyna decyzja w instalatorze.
5. Jeśli system poprosi o hasło administratora Maca, wpisz je i naciśnij
   Return. Podczas wpisywania w Terminalu nie pojawiają się kropki ani
   gwiazdki — to normalne.
6. Poczekaj na zielony komunikat i otwarcie aplikacji.

Okno pokazuje wyłącznie proste etapy. Pełne informacje techniczne trafiają do
prywatnego pliku:

```text
~/Library/Logs/O2 Mail Guardian/instalacja.log
```

Nie trzeba go otwierać, chyba że instalacja się nie powiedzie i poprosi o niego
osoba pomagająca rozwiązać problem.

Instalator może doinstalować Homebrew, Colimę, narzędzia kontenerowe i Go.
Jeżeli na Macu brakuje oficjalnych narzędzi Apple, sam otworzy ich systemowy
instalator; po jego zakończeniu wystarczy ponownie kliknąć `Install.command`.
Właściwy program zostanie umieszczony w:

```text
~/.local/bin/o2-mail-guardian/guardian
```

Nie przenoś ani nie usuwaj tego katalogu po instalacji.

Graficzna aplikacja zostanie zainstalowana w:

```text
~/Applications/O2 Mail Guardian.app
```

Pozostałe pliki są celowo rozdzielone:

- konfiguracja lokalnego stosu Rspamd/Colima:
  `~/.config/o2-mail-guardian`;
- baza stanu, zaszyfrowane archiwum i log:
  `~/Library/Application Support/O2 Mail Guardian`.

Nie przenoś ręcznie plików między tymi katalogami. `guardian status` pokazuje
ich aktualne położenie.

Instalator nie wykonuje automatycznego `chown -R` na całym `/opt/homebrew`.
Jeśli istniejący Homebrew ma problem z uprawnieniami, zatrzyma się i poprosi o
uruchomienie `brew doctor`, aby naprawić tylko wskazane katalogi.

Po instalacji nie musisz pamiętać komend. Instalator sam otwiera aplikację.
`Guardian.command`, `Uruchom-teraz.command` i `Sprawdz-stan.command` pozostają
awaryjnymi skrótami zgodnymi z wersją 0.2.

## Bezpieczna aktualizacja

Do aktualizacji również służy dwuklik na `Install.command`. Wersja 0.3.0:

1. instaluje tylko brakujące wymagania;
2. odczytuje i sprawdza wersję z pliku `VERSION`;
3. buduje Go i natywną aplikację do plików tymczasowych, testuje silnik Go i
   uruchamia wbudowaną, niezależną od wersji macOS samokontrolę aplikacji;
4. sprawdza istniejącą konfigurację bez pytania o zapisane hasło;
5. kopiuje `deploy` do nowego, losowego katalogu i waliduje Compose;
6. atomowo odsuwa poprzedni `deploy`, uruchamia nowy i czeka na oba porty
   Rspamd;
7. lokalnie podpisuje aplikację ad-hoc i sprawdza jej podpis;
8. atomowo podmienia `deploy`, backend i aplikację;
9. awaria w kontrolowanych punktach przywraca wszystkie poprzednie elementy;
10. wykonuje kontrolę, a następnie odświeża wcześniej zainstalowaną usługę.

Także przypadkowe zamknięcie Terminala, utrata okna lub `Ctrl+C` podczas
podmiany uruchamia ten sam rollback. Test wydania symuluje przerwanie sygnałem
i potwierdza przywrócenie silnika, aplikacji, konfiguracji oraz LaunchAgenta.

Usunięte z nowej wersji pliki `deploy` nie pozostają w aktywnym katalogu,
ponieważ aktualizacja nie nakłada nowej zawartości na starą. Wygenerowany hash
kontrolera pozostaje osobno w `~/.config/o2-mail-guardian/rspamd`.

Jeżeli `config.toml` jest poprawny, kreator `setup` nie jest uruchamiany
ponownie. Zachowane zostają konto, pęk kluczy, baza, archiwum i tryb pracy.
Jeżeli istniejąca konfiguracja jest nieczytelna, aktualizacja zatrzymuje się
przed zmianą działającego programu.

### Gdy macOS blokuje instalator

Kliknij `Install.command` z naciśniętym klawiszem Control, wybierz **Otwórz**,
a potem ponownie **Otwórz**. Rób to tylko dla pliku pobranego z zaufanego
wydania projektu. Nie stosuj porad polegających na całkowitym wyłączeniu
Gatekeepera.

## Krok 6: trzy ekrany konfiguracji

Kreator prowadzi przez tylko trzy ekrany:

1. **Konto** — wpisujesz adres i osobne hasło aplikacyjne. Przycisk pomocy
   otwiera właściwą instrukcję o2, a krótka podpowiedź przypomina o IMAP i 2FA.
2. **Wykryte ustawienia** — Guardian sam sprawdza szyfrowane połączenie, IMAP
   MOVE i folder SPAM. Jeden przycisk potwierdza układ i zapisuje ustawienia.
   Folder zmieniasz tylko po rozwinięciu opcji zaawansowanej, gdy wykrycie było
   błędne.
3. **Bezpieczna próba** — najpierw dry-run bez zmian, a dopiero po jego sukcesie
   przycisk uruchamiający ochronę co 2 godziny albo tryb ręczny.

Wewnątrz tych trzech ekranów Guardian nadal wykonuje wszystkie kontrole:

1. poprosi o pełny adres o2;
2. poprosi o hasło do programu pocztowego;
3. przekaże hasło przez standardowe wejście bezpośrednio do pęku kluczy
   macOS, bez umieszczania sekretu w argumentach procesu;
4. połączy się z `poczta.o2.pl` przez szyfrowany port 993;
5. wykryje rzeczywistą nazwę folderu SPAM i możliwości serwera;
6. pokaże pełne mapowanie Odebranych, systemowego SPAM-u i czterech folderów
   `AI-*`;
7. ostrzeże, jeśli wcześniejsze foldery uczące nie są puste; kliknięcie
   **Potwierdzam foldery i zapisuję** jest jawnym potwierdzeniem, że ich
   zawartość ma zostać potraktowana jako korekty;
8. utworzy cztery foldery `AI-*`;
9. wykona obowiązkowy dry-run bez MOVE, uczenia i kasowania;
10. dopiero po jego powodzeniu pokaże przycisk włączający automat co 2 godziny;
11. pozostawi tryb ochronny jako domyślny.

Jeżeli krok się nie powiedzie, można ponowić tylko ten krok albo wrócić.
Nieudany zapis hasła przywraca poprzedni wpis pęku kluczy albo usuwa nowy.
Zamknięcie aplikacji po udanym zapisie, ale przed dry-run, nie wymaga ponownego
podawania hasła — kreator wznowi pracę od bezpiecznej próby.
Tekstowy `guardian setup` pozostaje dostępny awaryjnie.

Hasło do o2 oraz losowe hasło kontrolera Rspamd nie pojawiają się w pliku
konfiguracyjnym, argumentach widocznych na liście procesów ani w
podsumowaniu. W pęku kluczy znajdują się również prywatny klucz
zaszyfrowanego archiwum i hasło kontrolera lokalnego Rspamd.

Jeżeli na dysku znajduje się wcześniejsza, niepusta baza albo pliki
`.eml.age`, a w pęku kluczy brakuje dotychczasowego klucza archiwum, kreator
zatrzyma się. Nie wygeneruje nowego klucza, ponieważ odciąłby dostęp do
wcześniejszych kopii. W takiej sytuacji odtwórz wcześniejszy pęk kluczy lub
skorzystaj z kopii Time Machine zamiast usuwać bazę czy archiwum.

## Krok 7: sprawdź instalację

W aplikacji otwórz **Pomoc** i kliknij **Pełna kontrola**. Nie trzeba używać
Terminala. Oczekiwany wynik to komunikat, że wszystkie kontrole zakończyły się
pomyślnie.

Poniższe polecenia są wyłącznie opcją awaryjną dla pomocy technicznej:

```bash
guardian doctor
guardian doctor --deep
guardian preflight
guardian status
```

Oczekiwany wynik:

- połączenie z IMAP: **OK**;
- natywne przenoszenie IMAP `MOVE`: **OK**;
- pęk kluczy: **OK**;
- Rspamd odpowiada i wykonuje kompletny skan testowy: **OK**;
- wszystkie cztery foldery `AI-*`: **OK**;
- tryb: **ochronny**;
- trwałe usuwanie: **wyłączone**.

`preflight` jest tylko kontrolą — nie przenosi wiadomości.

Na pulpicie znajduje się także **Sprawdź i napraw**. Odpowiada mu awaryjne
polecenie:

```bash
guardian napraw
```

Naprawa bezpiecznie uruchamia lokalny silnik, czeka maksymalnie przez
ograniczony czas na gotowość Rspamd, wykonuje kontrolę i dopiero po sukcesie
odświeża automatyczną usługę. Nie zmienia hasła i nie omija blokad
bezpieczeństwa poczty.
Wywołana z GUI zachowuje świadomie wybrany tryb ręczny; usługę można potem
włączyć osobnym przełącznikiem. Tylko interaktywny CLI może zadać pytanie,
czy włączyć automat podczas naprawy.
Przycisk **Pełna kontrola** sprawdza również Rspamd, Redis i DNS.

## Krok 8: włącz automatyczne działanie

Po udanym dry-run kliknij **Włącz ochronę co 2 godziny**. Możesz też świadomie
wybrać **Zakończ w trybie ręcznym** i sprawdzać pocztę przyciskiem w panelu.
Jeśli pominiesz automatyzację, wróć do **Ustawień** i włącz przełącznik
**Sprawdzaj skrzynkę co 2 godziny**. Poniższe polecenia są tylko awaryjne:

```bash
guardian service install
guardian service status
```

Polecenie `service install`, kreator terminalowy i funkcja naprawy korzystają
z tej samej trwałej bramki. Nie włączą automatu bez udanego dry-run. Ponowne
uruchomienie `guardian konfiguruj` zatrzymuje wcześniejszą usługę, wraca do
trybu ochronnego i wymaga nowej próby przed ponownym włączeniem harmonogramu.

Usługa uruchamia się po zalogowaniu do Maca. Gdy komputer śpi lub jest
wyłączony, nic się nie dzieje; pierwszy przebieg po obudzeniu nadrabia
zaległości.

## Pierwsza bezpieczna próba

```bash
guardian run --dry-run
```

Przejrzyj podsumowanie. Jeżeli nie ma błędów, uruchom normalny przebieg:

```bash
guardian run
```

W pierwszych 14 dniach obowiązuje tryb ochronny. Program zabezpiecza
wiadomości z systemowego SPAM-u o2 przed krótką retencją, ale nie usuwa poczty
na stałe. Po upływie 14 pełnych dni tryb aktywny nadal wymaga spełnienia
bramek jakości opisanych w [instrukcji obsługi](OBSLUGA.md). Sam upływ czasu
nie włącza go automatycznie.

Jeśli później wrócisz z trybu aktywnego do ochronnego, Guardian automatycznie
wyłączy trwałe usuwanie i rozpocznie nowy 14-dniowy okres obserwacji. Ponowne
wybranie ochrony, gdy program już jest w tym trybie, nie zeruje bieżącego
okresu.

## Zatrzymanie lub odinstalowanie

Zatrzymanie automatycznych przebiegów:

```bash
guardian service uninstall
```

Zatrzymanie lokalnego silnika:

```bash
guardian stack down
```

Przed pełnym usunięciem programu zachowaj foldery `AI-*` i lokalne kopie.
Następnie usuń w ustawieniach o2 hasło programu `O2 Mail Guardian`. To
natychmiast odbierze robotowi dostęp do skrzynki bez zmiany głównego hasła.
