#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_infra-common.sh"

trap 'fail "test silnika został przerwany (wiersz ${LINENO})."' ERR

header "sprawdzanie stanu silnika"
require_macos
setup_homebrew_path
require_command colima
require_command docker

if ! colima status >/dev/null 2>&1; then
  fail "Colima nie działa. Uruchom 02-uruchom-silnik.command."
fi

wait_for_docker
choose_compose

printf 'Colima:  '
green "działa"

printf '\nKontenery:\n'
compose ps

blue "Testuję Redis…"
[[ "$(docker --context colima exec o2-mail-guardian-redis redis-cli --raw ping)" == "PONG" ]] \
  || fail "Redis nie odpowiada."

blue "Testuję bezpieczne DNS…"
docker --context colima exec o2-mail-guardian-unbound drill-hc @127.0.0.1 dnssec.works >/dev/null \
  || fail "Unbound nie rozwiązuje poprawnie nazw DNS."

blue "Testuję konfigurację Rspamd…"
docker --context colima exec o2-mail-guardian-rspamd rspamadm configtest >/dev/null \
  || fail "konfiguracja Rspamd jest niepoprawna."

for rspamd_port in 11333 11334; do
  [[ "$(/usr/bin/curl -fsS --max-time 5 "http://127.0.0.1:${rspamd_port}/ping")" == "pong" ]] \
    || fail "lokalny port Rspamd ${rspamd_port} nie odpowiada."
done

green "Wszystkie testy zakończyły się powodzeniem."
printf '%s\n' "Panel diagnostyczny: http://127.0.0.1:11334"
notify_user "Wszystkie testy silnika zakończyły się powodzeniem."
pause_at_end
