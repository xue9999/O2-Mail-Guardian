# O2 Mail Guardian

Lokalny strażnik poczty o2.pl, który pomaga w obu najbardziej uciążliwych
sytuacjach:

- przenosi bardzo prawdopodobny spam z Odebranych do 30-dniowej kwarantanny;
- ratuje prawidłowe wiadomości błędnie umieszczone przez o2 w folderze SPAM;
- odkłada niejednoznaczne przypadki do ręcznego sprawdzenia;
- uczy się na podstawie dwóch prostych folderów: „to jest spam” i „to jest
  ważne”.

Program działa lokalnie na Macu. Nie korzysta z LLM, nie otwiera linków ani
załączników i nie wysyła treści wiadomości do usług chmurowych. Publiczna
usługa fuzzy Rspamd jest wyłączona — skróty treści wiadomości również nie
trafiają do zewnętrznej bazy fuzzy.

> **Najważniejsze:** przez pierwsze 14 dni Guardian tylko obserwuje i
> zabezpiecza pocztę. Trwałe usuwanie jest wyłączone. Nie zmieniaj ustawień
> zaawansowanych, dopóki aplikacja nie potwierdzi zakończenia okresu obserwacji
> i wszystkich kontroli jakości.

## Najprostszy start

### 1. Przygotuj konto o2

1. Zaloguj się do poczty o2 w przeglądarce.
2. Włącz dostęp IMAP: **Opcje → IMAP/POP → Włącz IMAP**.
3. Włącz logowanie dwustopniowe i zapisz klucze awaryjne.
4. Utwórz osobne hasło do programu pocztowego o nazwie np.
   `O2 Mail Guardian – Mac`.

Nie podawaj programowi zwykłego hasła do poczty. Szczegółowa instrukcja krok
po kroku znajduje się w
[instrukcji instalacji](docs/INSTALACJA.md).

### 2. Uruchom instalator

Jeżeli nie jesteś programistą, zacznij właśnie tutaj — nie trzeba wcześniej
otwierać Terminala ani wpisywać poleceń. Jeżeli otrzymałeś plik
**`O2-Mail-Guardian-0.3.0.zip`**, rozpakuj go i otwórz powstały folder. Są w
nim tylko instrukcja, licencja i instalator; techniczne składniki są celowo
ukryte. W Finderze kliknij dwukrotnie **`Install.command`**. Instalator:

- sprawdzi wymagania;
- zainstaluje potrzebne lokalne składniki;
- uruchomi bezpieczny stos Rspamd;
- zbuduje i lokalnie podpisze natywną aplikację;
- zainstaluje ją jako `~/Applications/O2 Mail Guardian.app`;
- otworzy graficzny kreator konfiguracji.

Po jednym potwierdzeniu zobaczysz tylko krótkie komunikaty o kolejnych etapach.
Szczegóły techniczne są zapisywane w prywatnym pliku
`~/Library/Logs/O2 Mail Guardian/instalacja.log`; nie trzeba ich śledzić ani
rozumieć. Przy pierwszej instalacji macOS może poprosić o hasło administratora,
ale instalator nigdy nie pyta w Terminalu o hasło do poczty.

Jeżeli macOS nie pozwoli otworzyć pliku, kliknij go z naciśniętym klawiszem
Control, wybierz **Otwórz**, a następnie ponownie **Otwórz**. Nie wyłączaj
globalnie zabezpieczeń macOS.

Ten sam `Install.command` służy do bezpiecznej aktualizacji. Jeśli działająca
konfiguracja już istnieje, instalator zachowuje konto, hasło w pęku kluczy,
bazę, archiwum i ustawienie automatycznej usługi. Nie uruchamia ponownie
kreatora hasła. Najpierw buduje i testuje wersję 0.3.0, a backend, aplikację
i konfigurację silnika podmienia dopiero po walidacji. Awaria w którymkolwiek
punkcie przywraca poprzedni komplet.

### 3. Przejdź przez kreator

Przygotuj:

- pełny adres e-mail o2;
- jednorazowo wyświetlone hasło do programu pocztowego;
- około 10 minut.

Graficzny kreator ma trzy krótkie ekrany: dane konta, automatycznie wykryte
bezpieczne ustawienia oraz obowiązkową próbę bez zmian. Folder SPAM wybierasz
ręcznie tylko wtedy, gdy automat wykrył go błędnie. Hasło płynie do backendu
wyłącznie przez stdin i trafia do pęku
kluczy macOS; nie pojawia się w argumentach, konfiguracji, odpowiedzi JSON ani
logu. Automat co 2 godziny zostanie włączony dopiero po udanej próbie i
kliknięciu **Włącz ochronę co 2 godziny**. Alternatywnie można zakończyć
kreator w trybie ręcznym; wtedy nic nie działa w tle, a sprawdzenie uruchamiasz
samodzielnie z pulpitu aplikacji.

Późniejsza zmiana hasła albo folderu SPAM również zatrzymuje automat,
wraca do trybu ochronnego i wymaga nowego dry-run. Wcześniejsze potwierdzenie
nie jest przenoszone na zmienioną konfigurację.

### 4. Otwieraj aplikację

Po instalacji aplikację znajdziesz w folderze **Aplikacje** w swoim katalogu
domowym. Ma normalne okno i ikonę w pasku menu. Pokazuje jeden z trzech stanów:
**Wszystko działa**, **Wymaga uwagi** albo **Nie działa**, a pod nim jedno
zalecane działanie.

Dwukrotne kliknięcie **`Guardian.command`** również otwiera aplikację. Dwa
dodatkowe skróty pozostają interfejsem awaryjnym:

- **`Uruchom-teraz.command`** — natychmiastowe bezpieczne sprawdzenie poczty;
- **`Sprawdz-stan.command`** — raport z ostatnich 24 godzin.

Awaryjne menu tekstowe można otworzyć w Terminalu:

```bash
guardian menu
```

GUI prowadzi przez sprawdzenie stanu, naukę, naprawę i odzyskiwanie wiadomości.
Jego wyłączenie przy logowaniu nie zatrzymuje niezależnej usługi skanującej.
Jeśli chcesz jedynie sprawdzić, czy wszystko działa:

```bash
guardian doctor
guardian doctor --deep
guardian status
```

## Codzienna obsługa

Po instalacji robot może działać automatycznie co 2 godziny. Użytkownik
potrzebny jest tylko przy pomyłkach:

| Sytuacja | Co zrobić w poczcie o2 |
|---|---|
| Spam pozostał w Odebranych | Przenieś go do `AI-Naucz-spam` |
| Ważna wiadomość trafiła do SPAM-u, kwarantanny lub sprawdzenia | Przenieś ją do `AI-Naucz-wazne` |
| Nie masz pewności | Pozostaw ją w `AI-Do-sprawdzenia` |
| Chcesz tylko podejrzeć zatrzymany spam | Otwórz `AI-Kwarantanna`; niczego nie klikaj w wiadomości |

Przy następnym przebiegu Guardian nauczy Rspamd poprawnej klasyfikacji. Dopiero
po udanym uczeniu przeniesie ważną wiadomość do Odebranych albo spam do
kwarantanny.

Lista **Zaufani** w o2 działa wyłącznie po stronie o2. Guardian jej nie
odczytuje i nie używa jej jako sygnału zaufania — każdą wiadomość ocenia na
podstawie jej rzeczywistych nagłówków i lokalnego filtra.

## Foldery tworzone przez program

- **`AI-Kwarantanna`** — bardzo prawdopodobny spam, przechowywany co najmniej
  30 dni przed ewentualnym usunięciem;
- **`AI-Do-sprawdzenia`** — przypadki niepewne i wiadomości, których nie udało
  się bezpiecznie przeskanować;
- **`AI-Naucz-spam`** — folder korekt: „ta wiadomość jest spamem”;
- **`AI-Naucz-wazne`** — folder korekt: „ta wiadomość jest prawidłowa”.

Nazwy nie zawierają polskich znaków celowo — dzięki temu działają poprawnie
również w starszych implementacjach IMAP.

## Przydatne polecenia

```bash
guardian menu
guardian napraw
guardian doctor
guardian preflight
guardian run --dry-run
guardian run
guardian status --since 24h
guardian mode status
guardian mode protect
guardian mode active
guardian archive list
guardian archive show <ID>
guardian archive restore <ID>
guardian purge --dry-run
guardian service status
guardian stack status
```

`--dry-run` oznacza próbę bez przenoszenia lub usuwania wiadomości.
Polecenie `archive show` pokazuje na żądanie tylko oczyszczone nagłówki
**Od**, **Temat** i **Data** z zaszyfrowanej kopii. Nie renderuje HTML, nie
otwiera odnośników ani załączników i nie zapisuje tych danych w bazie lub
logach.
Polecenie `archive restore` odtwarza kopię do `AI-Do-sprawdzenia`; nie wysyła
wiadomości do żadnego odbiorcy.

Jeżeli po przerwanym połączeniu `guardian status` pokaże „ruchy wymagające
uzgodnienia”, kolejne przebiegi sprawdzą źródło i cel. Program uzna ruch za
zakończony wyłącznie wtedy, gdy znajdzie jeden jednoznaczny wynik. Jeśli
licznik nie spada, pozostawi przypadek zablokowany bez kasowania — postępuj
według instrukcji rozwiązywania problemów.

## Dokumentacja

- [Instalacja krok po kroku](docs/INSTALACJA.md)
- [Graficzny panel i pierwsze kroki](docs/GUI-I-PIERWSZE-KROKI.md)
- [Codzienna obsługa i uczenie](docs/OBSLUGA.md)
- [Bezpieczeństwo, kopie i odzyskiwanie](docs/BEZPIECZENSTWO-I-ODZYSKIWANIE.md)
- [Architektura i prywatność](docs/ARCHITEKTURA-I-PRYWATNOSC.md)
- [Rozwiązywanie problemów](docs/ROZWIAZYWANIE-PROBLEMOW.md)

O2 Mail Guardian jest niezależnym projektem open source i nie jest produktem
ani oficjalną usługą o2/WP. Kod jest udostępniany na licencji
[MIT](LICENSE).
