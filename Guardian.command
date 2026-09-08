#!/bin/bash

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/scripts/_launcher-common.sh"

APP_DIR="${HOME}/Applications/O2 Mail Guardian.app"
if [[ -d "${APP_DIR}" ]]; then
  if /usr/bin/open "${APP_DIR}"; then
    exit 0
  fi
  launcher_red "Nie udało się otworzyć aplikacji. Uruchamiam awaryjne menu tekstowe."
fi

if ! ensure_guardian_installed; then
  launcher_pause
  exit 1
fi

if "${GUARDIAN_BIN}" menu; then
  exit 0
fi

launcher_red "Menu zakończyło się błędem. Żadna wiadomość nie została usunięta przez sam skrót."
if offer_guardian_repair; then
  "${GUARDIAN_BIN}" menu
  result=$?
else
  result=1
fi
launcher_pause
exit "${result}"
