#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_infra-common.sh"

trap 'fail "zatrzymywanie silnika zostało przerwane (wiersz ${LINENO})."' ERR

header "bezpieczne zatrzymywanie silnika"
require_macos
setup_homebrew_path
require_command docker

if ! docker --context colima info >/dev/null 2>&1; then
  yellow "Docker już nie działa. Nie ma czego zatrzymywać."
  pause_at_end
  exit 0
fi

choose_compose
blue "Zatrzymuję trzy kontenery…"
compose down --remove-orphans

green "Silnik został zatrzymany."
printf '%s\n' \
  "Nauczone dane Bayesa i konfiguracja pozostały zachowane." \
  "Ten skrypt nie usuwa wolumenów, haseł ani wiadomości."
notify_user "Silnik antyspamowy został zatrzymany."
pause_at_end
