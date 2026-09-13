# Zmiany w Mail Guardian

## 0.5.0

- Lokalny ZIP dla Apple Silicon zawiera gotowy backend i aplikację macOS.
  Instalowanie Guardiana z paczki nie kompiluje Go ani Swift.
- Manifest sprawdza kompletność payloadu, wersję, architekturę i sumy SHA-256;
  samokontrola i lokalne podpisy są sprawdzane przed podmianą programów.
- Wspólna blokada chroni przed równoległym instalowaniem i nadpisaniem logu.
- Wynik instalacji odróżnia sukces, potrzebę uwagi i awarię. Problem kontroli
  końcowej lub wznowienia harmonogramu pozostaje widoczny.
- Nieudane przywracanie zachowuje kopie aktualizacyjne i nie deklaruje sukcesu.
- Paczka zachowuje źródła; instalacja bezpośrednio z repozytorium nadal buduje
  program. Sumy kontrolne wykrywają uszkodzenia, nie uwierzytelniają wydawcy.
- Podpis ad hoc, bez Developer ID i notaryzacji. Minimalny deklarowany macOS 13;
  test na obecnym Macu nie potwierdza działania na wszystkich starszych wersjach.

## 0.4.0

Pierwsza iteracja poprawy designu i codziennej obsługi aplikacji macOS.

- Pulpit pokazuje zadania użytkownika przed statystykami. Ostatnie udane
  sprawdzenie i harmonogram są w karcie statusu, a postęp obserwacji ma jedną sekcję.
- Brak zapisanych wiadomości do oceny ma osobny komunikat, zależny od trybu
  automatycznego lub ręcznego; komunikat nie pojawia się przy nieaktualnych danych.
- Nauka i korekty prowadzą przez trzy kroki, pozwalają otworzyć pocztę o2
  w przeglądarce i uruchomić przetwarzanie już przeniesionych korekt u góry strony.
- Kopiowanie nazwy folderu wyświetla czasowe potwierdzenie.
- Odzyskiwanie objaśnia daty na liście i pozwala przechodzić między sąsiednimi
  kopiami na bieżącej stronie. Każda zmiana unieważnia odsłonięte nagłówki
  oraz możliwość przywrócenia poprzednio wybranej wiadomości.

- Archiwum pozwala wybrać daty Od/Do. Zakres obejmuje całe dni w lokalnej
  strefie czasu i łączy się z kategorią przed paginacją po stronie bazy.
  Zastosowanie filtra wraca do pierwszej strony i usuwa poprzedni podgląd.
- Ocena gotowości pokazuje pięć konkretnych warunków jakości oraz liczniki
  z bieżącego okresu obserwacji. Nie zmienia zasad aktywacji.

- Menu Przejdź i skróty ⌘1–⌘5 ułatwiają nawigację klawiaturą.
- Etykiety dostępności rozróżniają kopiowane foldery oraz spełnione
  i niespełnione warunki jakości.
- Błąd aktywacji pozostaje w otwartym oknie potwierdzenia; ponowienie
  nie wymaga ponownego wpisywania tekstu.

- Przygotowanie konta w kreatorze ma trzy czytelne kroki w rozwijanej sekcji.
  Pola danych są zablokowane podczas sprawdzania połączenia, aby wynik próby
  odpowiadał danym widocznym w formularzu.

- Ikona paska menu odróżnia obserwację od aktywnego porządkowania i pokazuje
  brak potwierdzenia stanu, gdy ostatni odczyt się nie udał.
- Test paczki sprawdza zgodność wersji i spakowanych widoków z kodem projektu.

- Puste wyniki odzyskiwania pozwalają bezpośrednio wyłączyć filtr dat lub
  pokazać wszystkie kategorie. Pusta dalsza strona ma powrót do początku listy.
- Błąd odczytu archiwum usuwa nieaktualną listę i blokuje nawigację stron.
  Ponowienie odczytu dotyczy strony, której wczytanie się nie udało.

- Anulowanie operacji nie jest traktowane jak sukces: okno aktywacji zachowuje
  potwierdzenie, a dalsze kroki uruchamiają się dopiero po udanej operacji
  i odczycie stanu. Przerwanie oznacza stan ochrony jako niepotwierdzony.
- Komunikat anulowania wyjaśnia, że zakończone kroki mogły zostać zapisane.
  Okno aktywacji pozwala odświeżyć stan przed ponowieniem.

### Dalsze prace

- Gotowa aplikacja podpisana Developer ID i notaryzowana zamiast lokalnego budowania.
- Audyt VoiceOver, klawiatury i testy użyteczności z osobami spoza projektu.

## 0.3.0

Pierwsze wydanie: lokalny silnik ochrony, natywna aplikacja macOS, kreator
konfiguracji, nauka, zaszyfrowane kopie i odzyskiwanie wiadomości.
