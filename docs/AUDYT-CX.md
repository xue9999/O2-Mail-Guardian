# Audyt doświadczenia użytkownika przed wydaniem

Testy interakcyjne wykonujemy w izolowanym podglądzie z `scripts/preview-gui.sh`.
Dane konta i hasło muszą być fikcyjne. Podgląd nie łączy się z prawdziwą
pocztą, pękiem kluczy ani usługą skanowania.

## Konfiguracja klawiaturą

Scenariusz: `unconfigured`.

1. Wpisz fikcyjny pełny adres o2. Tab powinien przejść do hasła.
2. Wpisz fikcyjne hasło. Enter powinien rozpocząć próbę połączenia i pokazać
   krok Foldery; nie może zapisać konfiguracji bez potwierdzenia folderów.
3. Potwierdź foldery. Oczekiwany krok: Bezpieczna próba, automat wyłączony.
4. Uruchom próbę. Wynik musi odróżniać symulację od rzeczywistego przenoszenia.
5. Wybierz tryb ręczny. Pulpit musi mówić, że sprawdzanie jest na żądanie.
6. Powtórz na świeżym podglądzie, wybierając harmonogram. Pulpit ma pokazać
   obserwację Odebranych, a nie aktywne porządkowanie.

Nie zmieniaj ustawień klawiatury całego systemu bez uzgodnienia z użytkownikiem.
Menu Przejdź powinno udostępniać ⌘1–⌘5 po konfiguracji i blokować je w kreatorze.

## Archiwum i filtry

Scenariusz: `healthy`.

- Odsłoń nagłówki kopii, zmień kopię: poprzednie nagłówki i możliwość
  przywrócenia mają zniknąć.
- Powtórz dla zmiany kategorii, strony i zastosowanego zakresu dat.
- Po zmianie dat bez kliknięcia Zastosuj lista nadal dotyczy jawnie
  wyświetlonego zastosowanego zakresu.
- Zakres bez wyników ma wyjaśniać, jak zmienić lub wyłączyć filtr.
- Błąd odczytu nie może być przedstawiony jako puste archiwum.
- W podglądzie `archive-error` odczyt listy kończy się błędem: oba przyciski
  paginacji muszą być zablokowane, a przycisk ponowienia widoczny.
- Przy pustych wynikach wyłącz filtr dat lub pokaż wszystkie kategorie
  przyciskiem pod komunikatem; lista i kontrolki filtrów muszą się zgadzać.
- Pusta dalsza strona nie może sugerować pustego archiwum. Powrót do pierwszej
  strony musi zachowywać kategorię i zastosowane daty.
- Zatwierdzenie przywrócenia dotyczy tylko aktualnie wybranej i odsłoniętej kopii.

## Stany ochrony i odzyskiwanie po błędach

Sprawdź podglądy `manual`, `active`, `ready`, `attention`, `critical`, `offline`.

- Ikona i tekst paska menu oraz pulpit muszą opisywać ten sam stan.
- Nieaktualne dane nie mogą odblokować aktywacji ani potwierdzać sprawności.
- Rozwijane warunki jakości mają wyjaśniać każdy niespełniony warunek.
- W razie błędu aktywacji okno ma pozostać otwarte z komunikatem i wpisanym
  potwierdzeniem. Anulowanie nie zmienia trybu.
- Anulowanie długiej operacji nie może być przedstawione jako jej sukces.
- Po przerwaniu operacji stan ochrony musi wymagać ponownego odczytu.
  Komunikat powinien wyjaśniać, że wcześniej zakończone kroki mogły zostać zapisane.
- Nieudany odczyt stanu po zmianie trybu nie zamyka okna aktywacji ani nie
  czyści potwierdzenia. Przycisk odświeżenia w tym oknie pozwala odzyskać
  aktualny stan bez ponownego wykonywania zmiany.

## Czytelność i dostępność

- Powtórz najważniejsze widoki przy minimalnym oknie 860 × 620 oraz w trybie
  ciemnym. Tekst i przyciski nie mogą się obcinać ani zachodzić na siebie.
- Sprawdź kolejność nawigacji klawiaturą i widoczność fokusu.
- W VoiceOver sprawdź nazwy pól, bieżący krok kreatora, kopiowany folder,
  stan warunków jakości, wybór kopii i komunikaty błędów.
- Odczyt drzewa dostępności pomaga wykrywać braki, ale nie zastępuje odsłuchu
  i nawigacji z rzeczywistym czytnikiem ekranu.

## Kryterium odbioru

Nie uznawaj całego audytu za zaliczony na podstawie kompilacji, testów modelu
lub pojedynczego skrótu. Każda ścieżka wymaga sprawdzenia końcowego rezultatu.
Po utracie transportu UI odczytaj bieżący stan przed ponowieniem akcji;
nie zakładaj, że akcja się nie wykonała. Po jednej próbie połączenia i resecie
sesji pozostaw test niepotwierdzony, jeśli transport nadal nie działa.
