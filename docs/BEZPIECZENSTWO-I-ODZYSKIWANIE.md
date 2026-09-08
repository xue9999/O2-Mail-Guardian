# Bezpieczeństwo, kopie i odzyskiwanie

## Co Guardian robi, a czego nie robi

Guardian:

- pobiera wiadomości przez szyfrowane IMAP;
- przesyła je tylko do lokalnego Rspamd;
- korzysta z lokalnego Bayesa i reguł Rspamd; publiczna usługa fuzzy jest
  wyłączona i nie otrzymuje skrótów treści;
- analizuje surowe nagłówki i treść bez wyświetlania HTML;
- przechowuje hasło do o2 w pęku kluczy macOS;
- zachowuje zaszyfrowaną kopię przed przeniesieniem do kwarantanny.

Guardian nie:

- wysyła wiadomości ani odpowiedzi;
- loguje się zwykłym hasłem do konta;
- odwiedza linków zawartych w wiadomościach;
- uruchamia lub otwiera załączników;
- przekazuje treści do OpenAI ani innej usługi LLM;
- ufa wyłącznie nazwie lub adresowi widocznemu w polu Od.

## Hasło do programu pocztowego

Hasło aplikacyjne daje dostęp do skrzynki, dlatego traktuj je jak klucz.

- Użyj hasła utworzonego wyłącznie dla Guardiana.
- Nie zapisuj go w Notatkach, e-mailu ani pliku tekstowym.
- Nie wklejaj go do zgłoszenia błędu.
- Kreator przekazuje je do narzędzia pęku kluczy przez standardowe wejście;
  wartość nie jest częścią argumentów procesu widocznych przez `ps`.
- Jeśli Mac zostanie zgubiony albo skradziony, usuń to hasło w ustawieniach
  konta o2.
- Po usunięciu hasła program natychmiast przestanie łączyć się ze skrzynką.

W ten sam sposób bez umieszczania sekretu w argumentach procesu zapisywane
jest losowe hasło lokalnego kontrolera Rspamd. W konfiguracji na dysku
znajduje się tylko jego nieodwracalny hash.

## Jak działa lokalna kopia

Przed przeniesieniem wiadomości do kwarantanny robot:

1. pobiera pełną wiadomość `.eml`;
2. oblicza jej skrót SHA-256;
3. szyfruje kopię kluczem przechowywanym w pęku kluczy;
4. sprawdza, czy zapis jest kompletny;
5. dopiero potem zezwala na przeniesienie.

Kopia jest przechowywana przez 35 dni. Standardowy okres kwarantanny wynosi
30 dni, więc pozostaje co najmniej pięciodniowy margines awaryjny. Zwykła baza
stanu nie zawiera treści, tematów ani adresów nadawców.

Nie kopiuj zaszyfrowanego archiwum na publiczny dysk ani nie usuwaj jego
klucza z pęku kluczy. Dokładne położenie archiwum i jego stan pokazuje:

```bash
guardian status
```

### Ochrona przed przypadkową zmianą klucza

Podczas ponownego `guardian setup` program najpierw sprawdza, czy istnieje
wcześniejsza baza lub dowolny plik `.eml.age`. Jeśli takie dane istnieją, ale
w pęku kluczy brakuje ich klucza, konfiguracja zostaje zatrzymana. Guardian
nie tworzy automatycznie nowego klucza, ponieważ stare kopie stałyby się
niemożliwe do odszyfrowania.

Nie usuwaj wówczas bazy ani archiwum. Odtwórz pęk kluczy z kopii Maca lub
Time Machine, a następnie ponownie uruchom `guardian setup`.

## Najprostsze odzyskanie przed usunięciem

Jeżeli ważna wiadomość nadal znajduje się w `AI-Kwarantanna` albo
`AI-Do-sprawdzenia`:

1. otwórz pocztę o2;
2. przenieś wiadomość do `AI-Naucz-wazne`;
3. uruchom `guardian run` albo poczekaj na kolejny automatyczny przebieg;
4. upewnij się, że wiadomość wróciła do Odebranych jako nieprzeczytana;
5. sprawdź w `guardian status`, czy korekta została przyjęta.

To jest lepsze od bezpośredniego przeciągnięcia do Odebranych, ponieważ filtr
uczy się na pomyłce.

## Odzyskanie po wykonaniu purge

Najłatwiej otworzyć:

```bash
guardian menu
```

Wybierz pozycję dotyczącą kopii i odzyskiwania. Menu pokaże identyfikatory
dostępnych kopii, których 35-dniowy okres jeszcze nie upłynął.

To samo można wykonać poleceniami:

```bash
guardian archive list
guardian archive restore <ID>
```

Jeżeli kopii jest więcej, `archive list` wypisze gotowe polecenie do
wyświetlenia następnej strony. W ten sposób starsze kopie pozostają dostępne
bez umieszczania tematów i adresów nadawców w bazie technicznej.

Zastąp `<ID>` dokładnym identyfikatorem wyświetlonym przez pierwsze polecenie.
Przywracanie:

- odszyfrowuje wybraną kopię;
- dodaje ją do `AI-Do-sprawdzenia` jako nieprzeczytaną;
- nie wysyła wiadomości i nie kontaktuje się z jej nadawcą.

Po sprawdzeniu przenieś prawidłową wiadomość z `AI-Do-sprawdzenia` do
`AI-Naucz-wazne`. Dzięki temu filtr nie powtórzy błędu. Jeżeli odzyskana
wiadomość rzeczywiście jest spamem, przenieś ją do `AI-Naucz-spam`.

Jeżeli kopia jest starsza niż 35 dni albo usunięto również lokalne archiwum i
klucz, Guardian nie będzie w stanie jej odzyskać. Dostawca o2 również
informuje, że wiadomości usuniętych z Kosza nie można przywrócić:
[odzyskiwanie wiadomości w o2](https://pomoc.o2.pl/odzyskanie-skasowanych-wiadomosci).

## Kiedy purge odmawia działania

To zamierzone zabezpieczenie. Wiadomość nie zostanie trwale usunięta, jeśli:

- nie minęło 30 pełnych dni w kwarantannie;
- zmienił się identyfikator folderu lub UID wiadomości;
- skrót wiadomości nie zgadza się ze stanem w bazie;
- brakuje poprawnej zaszyfrowanej kopii;
- ponowny skan nie potwierdził spamu;
- wiadomość została oznaczona jako ważna;
- wystąpił błąd IMAP, Rspamd, dysku albo bazy.

Nie omijaj tego ręcznym usuwaniem. Najpierw uruchom `guardian doctor`.

Jeżeli połączenie zostało przerwane podczas przenoszenia, program dodatkowo
uzgadnia lokalizację na podstawie pełnego skrótu wiadomości i Message-ID.
Więcej niż jedna zgodna kopia lub inny niejednoznaczny wynik blokuje
automatyczne sfinalizowanie ruchu i późniejszy purge.

## Szybkie zatrzymanie dostępu

W sytuacji awaryjnej:

1. usuń hasło `O2 Mail Guardian` w sekcji haseł do programów pocztowych o2;
2. uruchom:

```bash
guardian service uninstall
guardian stack down
```

Te działania nie usuwają wiadomości ani folderów `AI-*`.

## Co warto objąć kopią Time Machine

`guardian status` pokazuje katalog danych i katalog zaszyfrowanego archiwum.
Upewnij się, że nie zostały wyłączone z Time Machine. Sama kopia plików nie
wystarczy bez pęku kluczy, dlatego zadbaj także o możliwość odzyskania konta
użytkownika macOS.

Nie kopiuj zwykłego eksportu `.eml` do nieszyfrowanego katalogu. Może on
zawierać poufne załączniki i dane osobowe.
