#!/bin/bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/scripts/_launcher-common.sh"

if ! ensure_guardian_installed; then
  launcher_pause
  exit 1
fi

if ! "${GUARDIAN_BIN}" stack status >/dev/null 2>&1; then
  launcher_yellow "Lokalny silnik nie jest gotowy. Próbuję bezpiecznie go uruchomić…"
  if ! "${GUARDIAN_BIN}" stack up; then
    launcher_red "Nie udało się uruchomić lokalnego silnika."
    if ! offer_guardian_repair; then
      launcher_pause
      exit 1
    fi
  fi
fi

if "${GUARDIAN_BIN}" run; then
  launcher_green "Sprawdzanie skrzynki zakończyło się pomyślnie."
  result=0
else
  launcher_red "Sprawdzanie nie powiodło się. Program zachował zasadę „najpierw nie szkodzić”."
  if offer_guardian_repair; then
    launcher_yellow "Ponawiam sprawdzanie po udanej naprawie…"
    if "${GUARDIAN_BIN}" run; then
      launcher_green "Ponowne sprawdzanie zakończyło się pomyślnie."
      result=0
    else
      launcher_red "Ponowna próba także się nie udała. Otwórz aplikację O2 Mail Guardian i wybierz Sprawdź i napraw."
      result=1
    fi
  else
    result=1
  fi
fi

printf '\n'
launcher_pause
exit "${result}"
