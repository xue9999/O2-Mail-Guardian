#!/bin/bash

# Wspólne, proste komunikaty dla skrótów otwieranych dwuklikiem.

set -u

LAUNCHER_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
LAUNCHER_PROJECT_DIR="$(cd -- "${LAUNCHER_SCRIPT_DIR}/.." && pwd -P)"
GUARDIAN_BIN="${HOME}/.local/bin/o2-mail-guardian/guardian"

launcher_green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
launcher_yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }
launcher_red() { printf '\033[1;31m%s\033[0m\n' "$*" >&2; }

launcher_pause() {
  if [[ -t 0 ]]; then
    printf '\n'
    read -r -p "Naciśnij Enter, aby zamknąć to okno…" _
  fi
}

launcher_confirm() {
  local question="$1"
  local answer
  if [[ ! -t 0 ]]; then
    return 1
  fi
  read -r -p "${question} [T/n] " answer
  case "${answer:-T}" in
    [Nn]*) return 1 ;;
    *) return 0 ;;
  esac
}

ensure_guardian_installed() {
  if [[ -x "${GUARDIAN_BIN}" ]]; then
    return 0
  fi
  launcher_yellow "O2 Mail Guardian nie jest jeszcze zainstalowany."
  if [[ ! -f "${LAUNCHER_PROJECT_DIR}/Install.command" ]]; then
    launcher_red "W tym folderze brakuje Install.command. Pobierz ponownie pełną paczkę programu."
    return 1
  fi
  if ! launcher_confirm "Uruchomić teraz bezpieczny instalator?"; then
    launcher_yellow "Instalacja pominięta."
    return 1
  fi
  if ! GUARDIAN_LAUNCHED_FROM_SHORTCUT=1 /bin/bash "${LAUNCHER_PROJECT_DIR}/Install.command"; then
    launcher_red "Instalacja nie została zakończona. Przeczytaj czerwony komunikat powyżej."
    return 1
  fi
  if [[ ! -x "${GUARDIAN_BIN}" ]]; then
    launcher_red "Instalator zakończył pracę, ale program nadal nie jest dostępny."
    return 1
  fi
}

offer_guardian_repair() {
  launcher_yellow "Program może teraz wykonać bezpieczną naprawę bez zmieniania wiadomości."
  if ! launcher_confirm "Sprawdzić i naprawić program?"; then
    launcher_yellow "Naprawa pominięta. Żadna wiadomość nie została z tego powodu usunięta."
    return 1
  fi
  if ! "${GUARDIAN_BIN}" napraw; then
    launcher_red "Automatyczna naprawa nie rozwiązała problemu."
    launcher_red "Otwórz aplikację O2 Mail Guardian i w zakładce Pomoc zapisz bezpieczny raport."
    return 1
  fi
  launcher_green "Naprawa zakończyła się pomyślnie."
}
