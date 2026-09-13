#!/bin/bash
# Narrow seam for integration tests: file staging and validation remain real.
install_external() {
  local action="$1"; shift
  if [[ "${GUARDIAN_INSTALL_INTEGRATION_TEST:-0}" == 1 ]]; then
    case "$HOME" in /tmp/o2-guardian-installer-test.*) ;; *) return 90 ;; esac
    [[ "${GUARDIAN_INSTALL_TEST_DRIVER:-}" == "$HOME/driver.sh" ]] || return 90
    /bin/bash "$GUARDIAN_INSTALL_TEST_DRIVER" "$action" "$@"
    return $?
  fi
  if [[ "${GUARDIAN_INSTALL_SELF_TEST:-0}" == 1 ]]; then return 0; fi
  case "$action" in
    dependencies) /bin/bash "$PROJECT_DIR/scripts/01-zainstaluj-wymagania.command" ;;
    start-stack) /bin/bash "$PROJECT_DIR/scripts/02-uruchom-silnik.command" ;;
    compose) docker "$@" ;;
    launchctl) /bin/launchctl "$@" ;;
    open) /usr/bin/open "$@" ;;
    backend) "$@" ;;
    *) return 91 ;;
  esac
}
