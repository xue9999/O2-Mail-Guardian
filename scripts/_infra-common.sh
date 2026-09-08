#!/bin/bash

# Wspólne funkcje dla dwuklikalnych skryptów macOS.
# shellcheck disable=SC1111

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
DEPLOY_DIR="${PROJECT_DIR}/deploy"
RUNTIME_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/o2-mail-guardian"
if [[ -f "${RUNTIME_DIR}/deploy/compose.yaml" ]]; then
  COMPOSE_CONFIG_DIR="${RUNTIME_DIR}/deploy"
else
  COMPOSE_CONFIG_DIR="${DEPLOY_DIR}"
fi
COMPOSE_FILE="${COMPOSE_CONFIG_DIR}/compose.yaml"

export GUARDIAN_RUNTIME_DIR="${RUNTIME_DIR}"

blue() {
  printf '\033[1;34m%s\033[0m\n' "$*"
}

green() {
  printf '\033[1;32m%s\033[0m\n' "$*"
}

yellow() {
  printf '\033[1;33m%s\033[0m\n' "$*"
}

red() {
  printf '\033[1;31m%s\033[0m\n' "$*" >&2
}

header() {
  printf '\n'
  blue "O2 Mail Guardian — $*"
  printf '%s\n\n' "────────────────────────────────────────────"
}

pause_at_end() {
  if [[ "${GUARDIAN_SKIP_PAUSE:-0}" == "1" ]]; then
    return 0
  fi
  if [[ -t 0 ]]; then
    printf '\n'
    read -r -p "Naciśnij Enter, aby zamknąć to okno…" _
  fi
}

fail() {
  red "Nie udało się: $*"
  red "Nic nie zostało usunięte ze skrzynki ani z danych silnika."
  pause_at_end
  exit 1
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || fail "ten instalator jest przeznaczony dla macOS."
}

setup_homebrew_path() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    PATH="/opt/homebrew/bin:/opt/homebrew/sbin:${PATH}"
  elif [[ -x /usr/local/bin/brew ]]; then
    PATH="/usr/local/bin:/usr/local/sbin:${PATH}"
  fi
  export PATH
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "brakuje programu „$1”. Najpierw uruchom 01-zainstaluj-wymagania.command."
}

choose_compose() {
  if docker compose version >/dev/null 2>&1; then
    COMPOSE=(docker --context colima compose)
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE=(docker-compose)
  else
    fail "nie znaleziono Docker Compose. Uruchom ponownie instalator wymagań."
  fi
}

wait_for_docker() {
  local attempt
  for attempt in {1..60}; do
    # Jawny kontekst nie zmienia globalnego ustawienia Dockera użytkownika.
    if docker --context colima info >/dev/null 2>&1; then
      return 0
    fi
    : "${attempt}"
    sleep 2
  done
  fail "silnik Docker nie uruchomił się w ciągu dwóch minut."
}

compose() {
  DOCKER_CONTEXT=colima "${COMPOSE[@]}" --project-name o2-mail-guardian --file "${COMPOSE_FILE}" "$@"
}

wait_for_rspamd() {
  local attempt port healthy
  for attempt in {1..60}; do
    healthy=1
    for port in 11333 11334; do
      if [[ "$(/usr/bin/curl -fsS --max-time 2 "http://127.0.0.1:${port}/ping" 2>/dev/null || true)" != "pong" ]]; then
        healthy=0
        break
      fi
    done
    if (( healthy == 1 )); then
      return 0
    fi
    : "${attempt}"
    sleep 1
  done
  fail "Rspamd nie odpowiedział na lokalnych portach 11333 i 11334 w ciągu minuty."
}

notify_user() {
  local message="$1"
  /usr/bin/osascript -e "display notification \"${message//\"/\\\"}\" with title \"O2 Mail Guardian\"" >/dev/null 2>&1 || true
}
