#!/bin/bash

set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_HOME="$(/usr/bin/mktemp -d /tmp/o2-guardian-wrapper-test.XXXXXX)"
FAKE_CORE="${TEST_HOME}/fake-core.sh"
MARKER="${TEST_HOME}/core-ran"
cleanup() {
  case "${TEST_HOME}" in
    /tmp/o2-guardian-wrapper-test.*) /bin/rm -rf -- "${TEST_HOME}" ;;
  esac
}
trap cleanup EXIT

wrapper_lines="$(/usr/bin/wc -l < "${PROJECT_DIR}/Install.command")"
(( wrapper_lines <= 170 )) || {
  printf 'Widoczny instalator znów stał się zbyt złożony: %s wierszy.\n' "${wrapper_lines}" >&2
  exit 1
}
if /usr/bin/grep -Eiq 'docker|colima|go (test|build)|swift build|codesign|security add' "${PROJECT_DIR}/Install.command"; then
  printf 'Widoczny instalator zawiera ponownie szczegóły techniczne.\n' >&2
  exit 1
fi
for signal in HUP INT TERM; do
  /usr/bin/grep -Eq "trap on_signal .*${signal}|trap on_signal HUP INT TERM" "${PROJECT_DIR}/scripts/install-core.sh" || {
    printf 'Rdzeń instalatora nie chroni rollbacku przed sygnałem %s.\n' "${signal}" >&2
    exit 1
  }
done
if /usr/bin/grep -Fq 'scripts/test-swift.sh' "${PROJECT_DIR}/scripts/install-core.sh"; then
  printf 'Instalator znów zależy od deweloperskiego frameworka testów Swift.\n' >&2
  exit 1
fi
/usr/bin/grep -Fq -- '--self-test' "${PROJECT_DIR}/scripts/install-core.sh"
for message in \
  'Sprawdzam, czy ten Mac jest gotowy.' \
  'Przygotowuję brakujące składniki.' \
  'Sprawdzam nową wersję przed instalacją' \
  'Przygotowuję okno aplikacji' \
  'Przygotowuję lokalną ochronę antyspamową' \
  'Umieszczam aplikację w folderze Aplikacje'; do
  /usr/bin/grep -Fq "${message}" "${PROJECT_DIR}/scripts/install-core.sh" || {
    printf 'Brakuje prostego komunikatu instalatora: %s\n' "${message}" >&2
    exit 1
  }
done

printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "→ Etap testowy" >&3' \
  'printf "%s\n" "technical-only-detail" >&2' \
  'printf "%s\n" "uruchomiono" > "${WRAPPER_TEST_MARKER}"' \
  'if [[ "${WRAPPER_TEST_RESULT:-success}" == "failure" ]]; then' \
  '  printf "%s\n" "Bezpieczny opis testowej awarii." > "${GUARDIAN_INSTALL_STATUS_FILE}"' \
  '  exit 23' \
  'fi' \
  'if [[ "${WRAPPER_TEST_RESULT:-success}" != missing ]]; then printf "%s\n" "${WRAPPER_TEST_RESULT:-success}" > "${GUARDIAN_INSTALL_RESULT_FILE}"; fi' > "${FAKE_CORE}"

common_env=(
  HOME="${TEST_HOME}"
  GUARDIAN_INSTALL_WRAPPER_TEST=1
  GUARDIAN_INSTALL_TEST_CORE="${FAKE_CORE}"
  GUARDIAN_INSTALL_CONFIRMED=1
  GUARDIAN_SKIP_PAUSE=1
  WRAPPER_TEST_MARKER="${MARKER}"
)

success_output="$(env "${common_env[@]}" WRAPPER_TEST_RESULT=success /bin/bash "${PROJECT_DIR}/Install.command" 2>&1)"
[[ "${success_output}" == *"Etap testowy"* ]]
[[ "${success_output}" == *"Gotowe"* ]]
[[ "${success_output}" != *"technical-only-detail"* ]]
/usr/bin/grep -Fq "technical-only-detail" "${TEST_HOME}/Library/Logs/O2 Mail Guardian/instalacja.log"

failure_output="$(env "${common_env[@]}" WRAPPER_TEST_RESULT=failure /bin/bash "${PROJECT_DIR}/Install.command" 2>&1 || true)"
[[ "${failure_output}" == *"Bezpieczny opis testowej awarii."* ]]
[[ "${failure_output}" != *"technical-only-detail"* ]]
[[ "${failure_output}" == *"Przeczytaj wskazówkę powyżej"* ]]

/bin/rm -f -- "${MARKER}"
cancel_output="$(printf 'N\n' | env \
  HOME="${TEST_HOME}" \
  GUARDIAN_INSTALL_WRAPPER_TEST=1 \
  GUARDIAN_INSTALL_TEST_CORE="${FAKE_CORE}" \
  GUARDIAN_SKIP_PAUSE=1 \
  WRAPPER_TEST_MARKER="${MARKER}" \
  /bin/bash "${PROJECT_DIR}/Install.command" 2>&1)"
[[ "${cancel_output}" == *"niczego nie zmieniono"* ]]
[[ ! -e "${MARKER}" ]]

# Guardian.command już pyta, czy uruchomić instalację. Przekazanie tej zgody
# nie może powodować drugiego, identycznego pytania w Install.command.
shortcut_output="$(env \
  HOME="${TEST_HOME}" \
  GUARDIAN_INSTALL_WRAPPER_TEST=1 \
  GUARDIAN_INSTALL_TEST_CORE="${FAKE_CORE}" \
  GUARDIAN_LAUNCHED_FROM_SHORTCUT=1 \
  GUARDIAN_SKIP_PAUSE=1 \
  WRAPPER_TEST_MARKER="${MARKER}" \
  /bin/bash "${PROJECT_DIR}/Install.command" </dev/null 2>&1)"
[[ "${shortcut_output}" == *"Gotowe"* ]]
[[ -e "${MARKER}" ]]

permissions="$(/usr/bin/stat -f '%Lp' "${TEST_HOME}/Library/Logs/O2 Mail Guardian/instalacja.log")"
[[ "${permissions}" == "600" ]]

attention_output="$(env "${common_env[@]}" WRAPPER_TEST_RESULT=attention /bin/bash "${PROJECT_DIR}/Install.command" 2>&1)"
[[ "$attention_output" == *"ochrona wymaga uwagi"* && "$attention_output" != *"Gotowe"* ]]
if env "${common_env[@]}" WRAPPER_TEST_RESULT=missing /bin/bash "${PROJECT_DIR}/Install.command" >"$TEST_HOME/missing-output" 2>&1; then exit 1; fi
/usr/bin/grep -q 'Nie potwierdzono' "$TEST_HOME/missing-output"

lock="$TEST_HOME/Library/Logs/O2 Mail Guardian/install.lock"
mkdir "$lock"
printf '999999\n' > "$lock/owner"
before="$(shasum "$TEST_HOME/Library/Logs/O2 Mail Guardian/instalacja.log")"
if env "${common_env[@]}" /bin/bash "$PROJECT_DIR/Install.command" > "$TEST_HOME/stale-output" 2>&1; then exit 1; fi
[[ "$(cat "$lock/owner")" == 999999 ]]
[[ "$(shasum "$TEST_HOME/Library/Logs/O2 Mail Guardian/instalacja.log")" == "$before" ]]
grep -q 'Monitorze aktywności' "$TEST_HOME/stale-output"

printf 'Prosty interfejs instalatora: OK\n'
