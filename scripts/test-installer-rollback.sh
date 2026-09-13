#!/bin/bash

set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_HOME="$(/usr/bin/mktemp -d /tmp/o2-guardian-installer-test.XXXXXX)"
cleanup() {
  case "${TEST_HOME}" in
    /tmp/o2-guardian-installer-test.*) /bin/rm -rf -- "${TEST_HOME}" ;;
  esac
}
trap cleanup EXIT

HOME="${TEST_HOME}" \
XDG_CONFIG_HOME="${TEST_HOME}/config" \
GUARDIAN_INSTALL_SELF_TEST=1 \
/bin/bash "${PROJECT_DIR}/Install.command"

if HOME="${TEST_HOME}" \
   XDG_CONFIG_HOME="${TEST_HOME}/config" \
   GUARDIAN_INSTALL_SELF_TEST=1 \
   GUARDIAN_INSTALL_SIGNAL_SELF_TEST=1 \
   /bin/bash "${PROJECT_DIR}/Install.command"; then
  printf 'Test sygnału powinien zakończyć instalator błędem.\n' >&2
  exit 1
fi

/usr/bin/grep -Fqx 'old-deploy' "${TEST_HOME}/config/o2-mail-guardian/deploy/marker"
/usr/bin/grep -Fqx 'old-binary' "${TEST_HOME}/.local/bin/o2-mail-guardian/guardian"
/usr/bin/grep -Fqx 'old-app' "${TEST_HOME}/Applications/O2 Mail Guardian.app/Contents/marker"
/usr/bin/grep -Fqx 'old-ui' "${TEST_HOME}/Library/LaunchAgents/pl.o2.mail-guardian-ui.plist"
printf 'Rollback po przerwaniu Terminala: OK.\n'

STATUS_FILE="${TEST_HOME}/friendly-status.txt"
if HOME="${TEST_HOME}" \
   XDG_CONFIG_HOME="${TEST_HOME}/config" \
   GUARDIAN_INSTALL_SELF_TEST=1 \
   GUARDIAN_INSTALL_ERROR_SELF_TEST=1 \
   GUARDIAN_INSTALL_STATUS_FILE="${STATUS_FILE}" \
   /bin/bash "${PROJECT_DIR}/Install.command" >/dev/null 2>&1; then
  printf 'Test zwykłego błędu powinien zakończyć instalator błędem.\n' >&2
  exit 1
fi
/usr/bin/grep -Fq 'bezpieczny test nazwy etapu' "${STATUS_FILE}"
if /usr/bin/grep -Eiq 'wiersz|linia|line [0-9]' "${STATUS_FILE}"; then
  printf 'Widoczny opis błędu zawiera szczegół kodu zamiast nazwy etapu.\n' >&2
  exit 1
fi
printf 'Przyjazny opis nieprzewidzianego błędu: OK.\n'

if HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/config" GUARDIAN_INSTALL_SELF_TEST=1 \
   GUARDIAN_INSTALL_ROLLBACK_FAILURE_TEST=1 GUARDIAN_INSTALL_STATUS_FILE="$STATUS_FILE" \
   /bin/bash "$PROJECT_DIR/Install.command" > "$TEST_HOME/rollback-failed" 2>&1; then exit 1; fi
grep -q 'Przywracanie poprzedniej instalacji nie powiodło się' "$STATUS_FILE"
[[ -n "$(find "$TEST_HOME/.local/bin/o2-mail-guardian" -name '*.saved' -print)" ]]
printf 'Nieudany rollback zachowuje kopię i zgłasza brak potwierdzenia: OK\n'
