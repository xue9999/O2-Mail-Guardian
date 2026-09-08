# Graficzny panel i pierwsze kroki

## Pierwsza konfiguracja — trzy ekrany

1. Wpisz adres o2 i osobne hasło aplikacyjne, a następnie kliknij **Połącz i
   wykryj ustawienia**.
2. Sprawdź automatycznie wykryty folder SPAM i kliknij
   **Potwierdzam foldery i zapisuję**. Listę folderów rozwijaj tylko,
   jeśli wykryta nazwa jest nieprawidłowa. Lista nie pokazuje Odebranych,
   folderów Guardiana ani technicznych pozycji, których nie wolno wybrać.
   Nazwy czterech dodatkowych folderów ochronnych są dostępne pod
   **Pokaż nazwy folderów Guardiana**, ale nie trzeba ich rozwijać.
3. Kliknij **Wykonaj bezpieczną próbę**. Dopiero po sukcesie wybierz ochronę co
   2 godziny albo świadomy tryb ręczny.

Pięć wymaganych kontroli bezpieczeństwa — konto, połączenie, folder SPAM,
układ folderów i dry-run — nadal jest wykonywanych, ale nie wymaga przechodzenia
przez pięć osobnych ekranów.

## Co zobaczysz po otwarciu

O2 Mail Guardian pokazuje jeden czytelny stan:

- **Wszystko działa** — automat ma świeży udany przebieg;
- **Wymaga uwagi** — ostatni sukces był ponad 4 godziny temu albo pozostał
  przypadek do uzgodnienia;
- **Nie działa** — nie było sukcesu od ponad 48 godzin;
- **Tryb ręczny** — automat jest świadomie wyłączony.

Pod stanem zawsze znajduje się jedno zalecane następne działanie. Przycisk
**Sprawdź skrzynkę teraz** uruchamia pełny, bezpieczny przebieg, a **Sprawdź i
napraw** kontroluje lokalny silnik i konfigurację. Długą operację można
anulować; zapisane wcześniej intencje i nierozstrzygnięte ruchy zostaną
uzgodnione przy następnym przebiegu.

Komunikat o odrzuconym logowaniu ma przycisk otwierający właściwą instrukcję
o2. Komunikat o zatrzymanej lokalnej ochronie ma bezpośredni przycisk
**Sprawdź i napraw**. Kody techniczne pozostają jedynie informacją dla osoby
pomagającej rozwiązać problem.

## Zakładki

- **Pulpit** — ostatnia próba i sukces, stan automatu, tryb ochrony i liczniki;
- **Nauka** — dokładna instrukcja użycia `AI-Naucz-spam` i
  `AI-Naucz-wazne` oraz przycisk przetwarzający korekty;
- **Odzyskiwanie** — 10 technicznych wpisów na stronę; przywrócenie do
  `AI-Do-sprawdzenia` odblokowuje się dopiero po obejrzeniu oczyszczonego
  podglądu trzech nagłówków i wymaga osobnego potwierdzenia;
- **Ustawienia** — automat skanowania, start samego panelu po zalogowaniu,
  konto oraz zwinięta sekcja zaawansowana. Na co dzień nie trzeba jej
  otwierać; zawiera ona osobno zabezpieczone przenoszenie wiadomości i trwałe
  usuwanie;
- **Pomoc** — głęboka kontrola i zredagowany pakiet diagnostyczny.

GUI nigdy nie dostaje treści e-maila, HTML, odnośników ani załączników. Pełną
wiadomość widzi wyłącznie lokalny backend Go i lokalny Rspamd. Hasło
aplikacyjne jest przesyłane do backendu przez stdin i nie wraca w JSON-ie.

## Ikona w pasku menu

Ikona pokazuje tekstowy stan oraz cztery bezpieczne czynności: otwarcie
panelu, sprawdzenie skrzynki, naprawę i pauzę/wznowienie automatu. Celowo nie
ma tam trwałego usuwania ani odzyskiwania.

Wyłączenie opcji **Uruchamiaj panel po zalogowaniu** dotyczy tylko okna i
ikony. Nie zatrzymuje niezależnego sprawdzania poczty co 2 godziny.

Ponowne zapisanie hasła lub zmiana folderu SPAM przez kreator zatrzymuje automat,
przywraca tryb ochronny i unieważnia poprzednią próbę. Po zmianie trzeba
ponownie wykonać dry-run i świadomie kliknąć **Włącz ochronę co 2 godziny**.
Po zapisaniu nowych ustawień kreator pozostaje otwarty aż do zakończenia próby,
więc przycisk uruchomienia automatu nie znika samoczynnie. Można też wybrać
**Zakończ w trybie ręcznym**; wtedy poczta będzie sprawdzana tylko na żądanie.
Jeżeli konfiguracja nie powiedzie się, Guardian próbuje przywrócić poprzednią
konfigurację, sekret z pęku kluczy oraz wcześniejszy automat.

Na pulpicie techniczny tryb `protect` jest pokazany jako **Tylko obserwacja**,
a `active` jako **Przenoszenie włączone**. Ustawienia te znajdują się pod
**Ustawienia zaawansowane — zwykle nie trzeba ich zmieniać**. Trwałe usuwanie
pozostaje tam wyłączone i nadal wymaga wpisania osobnego potwierdzenia.

Jeśli zamkniesz aplikację już po zapisaniu konta, ale przed ukończeniem
bezpiecznej próby, następne uruchomienie wróci od razu do kroku 3. Nie trzeba
ponownie wpisywać adresu ani hasła; automat nadal pozostaje wyłączony.
