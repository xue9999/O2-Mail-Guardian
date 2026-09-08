#!/bin/bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/scripts/_launcher-common.sh"

if ! ensure_guardian_installed; then
  launcher_pause
  exit 1
fi

if "${GUARDIAN_BIN}" status --since 24h; then
  result=0
else
  launcher_red "Nie udało się odczytać stanu. Żadna wiadomość nie została zmieniona."
  if offer_guardian_repair; then
    "${GUARDIAN_BIN}" status --since 24h
    result=$?
  else
    result=1
  fi
fi

launcher_pause
exit "${result}"
