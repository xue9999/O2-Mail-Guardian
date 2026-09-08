# Architektura i prywatność

Ten dokument opisuje techniczne założenia projektu. Do zwykłej obsługi nie
jest potrzebny.

## Przepływ wiadomości

```text
o2 IMAP (TLS)
      │
      ▼
Guardian ──pełny RFC822──► lokalny Rspamd
      │                         │
      │                         └── Redis/Bayes + lokalny DNS
      │
      ├── szyfrowana kopia age
      ├── zanonimizowany stan SQLite
      └── bezpieczny IMAP MOVE
```

Natywna aplikacja SwiftUI nie łączy się bezpośrednio z IMAP, Keychain,
SQLite ani Rspamd. Wywołuje lokalne `guardian api` w protokole 1. Każda
odpowiedź ma `protocol`, `ok` i `data` albo ustrukturyzowany `error` z kodem,
ważnością i jedną poradą. Wejście ma limit 64 KiB, wyjście aplikacji 2 MiB,
a hasło konfiguracji trafia wyłącznie na stdin.

Guardian nie ma kodu SMTP, nie odwiedza adresów z wiadomości, nie renderuje
HTML i nie wykonuje załączników. Rspamd nasłuchuje tylko na `127.0.0.1`;
Redis i Unbound są dostępne wyłącznie w prywatnej sieci kontenerów.
Wszystkie trzy kontenery działają z `no-new-privileges`, usuwają domyślnie
wszystkie Linux capabilities i mają system plików tylko do odczytu; Unbound
odzyskuje wyłącznie trzy minimalne capabilities potrzebne do uruchomienia DNS.
Po każdym wdrożeniu instalator wykonuje `rspamadm configtest` na rzeczywiście
uruchomionym kontenerze, zanim uzna lokalny silnik za gotowy.

Unbound wykonuje zwykłe internetowe zapytania DNS potrzebne m.in. do
sprawdzenia DKIM oraz reputacji domen. Nie pobiera stron ani nie wysyła treści
wiadomości, ale nazwa domeny znaleziona w nagłówku lub odnośniku może być
widoczna dla obsługujących ją serwerów DNS. Jest to ta sama klasa metadanych,
z której korzystają klasyczne filtry antyspamowe.

Moduły publicznego fuzzy oraz śledzenia przekierowań URL w Rspamd są jawnie
wyłączone. Guardian nie wysyła skrótów treści do publicznych serwerów fuzzy
i nie próbuje rozwijać odnośników. Uczenie odbywa się wyłącznie w lokalnym
Redis/Bayes na podstawie wiadomości ręcznie przeniesionych do folderów
uczących.

Lista **Zaufani** o2 nie jest dostępna przez interfejs używany przez program i
nie stanowi sygnału zaufania Guardiana. Kontrola lokalna opiera się na
wiadomości, jej uwierzytelnieniu oraz modelu nauczonym przez użytkownika.

## Kolejność bezpiecznego przenoszenia

1. Pobrać wiadomość bez ustawiania flagi „przeczytana”.
2. Obliczyć SHA-256.
3. Zaszyfrować pełną kopię kluczem `age` przechowywanym w pęku kluczy.
4. Zweryfikować kopię przez odszyfrowanie i ponowne obliczenie SHA-256.
5. Zapisać w SQLite stan `pending_move`.
6. Wykonać IMAP MOVE.
7. Dopiero po potwierdzeniu serwera zapisać folder i UID docelowy.

Bezpośrednio przed każdym `MOVE`, STORE flag i `UID EXPUNGE` klient ponownie
wykonuje SELECT i porównuje oczekiwane `UIDVALIDITY`. Zmiana wartości zwraca
kod `IMAP_UIDVALIDITY` i blokuje mutację.

Guardian wymaga natywnego IMAP `MOVE`, reklamowanego bezpośrednio albo przez
IMAP4rev2. Samo `UIDPLUS` nie wystarcza do przenoszenia: biblioteczny fallback
`COPY`/`\Deleted` jest celowo odrzucony, ponieważ utrata połączenia pomiędzy
tymi krokami utrudniałaby bezpieczne potwierdzenie kopii. Jeżeli natywne
`MOVE` powiedzie się, lecz odpowiedź serwera zaginie lub nie zawiera
jednoznacznego docelowego UID, zapis pozostaje w stanie `pending_move` i musi
zostać uzgodniony przed jakimkolwiek działaniem destrukcyjnym. Program nie
używa zwykłego, obejmującego cały folder `EXPUNGE`, który mógłby usunąć inne
wiadomości oznaczone wcześniej przez użytkownika.

### Uzgadnianie przerwanego ruchu

Stan `pending_move` jest zapisywany przed poleceniem MOVE. Jeśli odpowiedź
serwera zaginie, kolejny przebieg nie zgaduje wyniku. Przeszukuje cały folder
źródłowy i docelowy, porównując SHA-256 pełnego RFC822 oraz skrót Message-ID.

- dokładnie jedna kopia docelowa przy braku źródłowej pozwala sfinalizować
  zapis docelowego UID;
- jedna kopia źródłowa przy braku docelowej pozwala ponowić wyłącznie
  wcześniej zapisany ruch;
- kopia po obu stronach, wiele zgodnych kopii lub brak jednoznacznego wyniku
  zapisuje stan niejednoznaczny i blokuje destrukcyjne działania.

Foldery są przeglądane stronami obejmującymi najwyżej 250 wartości UID, z
trwałym kursorem w SQLite i łącznym budżetem 60 sekund na przebieg. Najpierw
porównywany jest rozmiar i skrót Message-ID, a pełny SHA-256 tylko dla
kandydatów. Kolejne przebiegi ponawiają tę kontrolę w trybie tylko do odczytu. Jeśli układ
stanie się jednoznaczny, stan może zostać sfinalizowany; jeśli nadal pasują
kopie po obu stronach, pozostaje niedestrukcyjny i wymaga diagnostyki.

## Dane zapisane lokalnie

- `config.toml`: adres konta, nazwy folderów, progi i ścieżki; bez haseł;
- `guardian.db`: UID, UIDVALIDITY, skróty SHA-256 i decyzje; bez tematów,
  nadawców i treści;
- `archive/*.eml.age`: zaszyfrowane pełne kopie wiadomości;
- `guardian.log`: liczby operacji i błędy techniczne; bez treści wiadomości.
- `service-health.json`: atomowy heartbeat bez danych poczty — ostatnia próba,
  etap, kod błędu i ostatni sukces.

Hasło aplikacyjne o2, hasło kontrolera Rspamd i prywatny klucz archiwum
znajdują się w pęku kluczy macOS.

Polecenie `guardian archive show <ID>` odszyfrowuje wskazaną kopię na żądanie,
ale wypisuje wyłącznie oczyszczone nagłówki Od, Temat i Data. Pełne sekwencje
sterujące ANSI są usuwane; treść, HTML, odnośniki i załączniki nie są
wyświetlane ani otwierane. Pokazane nagłówki nie trafiają do SQLite ani
logów.

Sekrety zapisywane przez program i skrypt silnika są podawane narzędziu
pęku kluczy przez standardowe wejście. Nie są elementem argumentów procesu.
Plik kontrolera Rspamd zawiera wyłącznie hash hasła.

Jeśli istnieje wcześniejsza baza albo pliki `.eml.age`, konfigurator odmawia
wygenerowania zastępczego klucza archiwum. Chroni to przed cichą utratą
możliwości odszyfrowania istniejących kopii.

## Warunki trwałego usunięcia

Purge wymaga jednocześnie:

- świeżego, co najmniej 14-dniowego okresu ochronnego spełniającego bramki
  jakości oraz późniejszych 30 dni trybu aktywnego;
- co najmniej 30 dni kwarantanny;
- istniejącej i poprawnie odszyfrowanej kopii;
- zgodności folderu, UID, UIDVALIDITY, skrótu Message-ID oraz SHA-256;
- ponownego wyniku `spam` z Rspamd;
- UIDPLUS, aby usunąć dokładnie jeden wskazany UID.
- pustego folderu `AI-Naucz-wazne` i braku trwałej intencji korekty `ham`.

Intencja `ham` lub `spam` trafia do SQLite przed wywołaniem Rspamd. Awaria
`/learnham` nie odbiera więc ważnej wiadomości stałego veto wobec purge.
Uwierzytelniony `/stat` zapisuje najwyższe potwierdzone rewizje `BAYES_SPAM`
i `BAYES_HAM`. Cofnięcie licznika wyłącza purge, przywraca ochronę i rozpoczyna
nowy okres obserwacji.

Po usunięciu wiadomości kopia lokalna pozostaje do 35. dnia. Kopia nie jest
usuwana, jeśli wiadomość nadal istnieje albo jej stan jest niejednoznaczny.

Powrót z trybu aktywnego do ochronnego automatycznie wyłącza purge i
rozpoczyna nowy 14-dniowy okres. Samo ponowne wybranie już działającego trybu
ochronnego nie resetuje daty.

## Niezawodność operacyjna

- Aktualizacja buduje i testuje kandydata przed zmianą aktywnej instalacji.
- Katalog `deploy` jest przygotowywany obok aktywnego i podmieniany przez
  operacje `rename`; nie jest nakładany przez `ditto` na stare pliki.
- Nieudane uruchomienie nowego stosu przywraca poprzedni katalog `deploy`;
  poprzednia binarka jest zachowana jako `guardian.previous`.
- LaunchAgent przed skanem wykonuje niedestrukcyjne `stack up`, a wszystkie
  długie polecenia Colimy, Dockera i kontrole HTTP mają ograniczony czas.
- Rspamd musi odpowiedzieć `pong` na portach 11333 i 11334, zanim naprawa
  przejdzie do kontroli skrzynki.
- Ogólne powiadomienie o błędzie nie zawiera danych wiadomości i jest
  ograniczone do jednego na dobę.
- Log o rozmiarze ponad 5 MiB jest rotowany z zachowaniem dwóch poprzednich
  plików.
- Runner otwiera bieżący log dopiero po rotacji, więc nowy przebieg nie zapisuje
  do przeniesionego pliku `.1`.
- Jawny `docker --context colima` nie zmienia globalnego kontekstu Dockera.
- Colima jest uruchamiana na żądanie z `--activate=false`; projekt nie
  rejestruje jej jako osobnej usługi `brew services`.
