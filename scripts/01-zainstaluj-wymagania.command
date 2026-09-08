#!/bin/bash

set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd -P)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/_infra-common.sh"

trap 'fail "instalacja wymagań została przerwana (wiersz ${LINENO})."' ERR

header "instalacja wymaganych programów"
require_macos
setup_homebrew_path

printf '%s\n' \
  "Ten krok instaluje bezpłatne narzędzia Homebrew, Colima, Docker i Compose." \
  "Nie łączy się ze skrzynką pocztową i nie zmienia żadnych wiadomości."
printf '\n'
if [[ "${GUARDIAN_NONINTERACTIVE:-0}" != "1" ]]; then
  read -r -p "Kontynuować? [T/n] " answer
  case "${answer:-T}" in
    [Nn]*) yellow "Instalacja anulowana."; pause_at_end; exit 0 ;;
  esac
fi

if ! command -v brew >/dev/null 2>&1; then
  blue "Instaluję Homebrew z oficjalnego instalatora…"
  NONINTERACTIVE=1 /bin/bash -c "$(/usr/bin/curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  setup_homebrew_path
fi

command -v brew >/dev/null 2>&1 || fail "Homebrew nie jest dostępny po instalacji."
if ! brew config >/dev/null 2>&1; then
  fail "Homebrew jest zainstalowany, ale nie działa poprawnie. Uruchom w Terminalu „brew doctor” i popraw tylko wskazane przez niego katalogi; instalator nie zmienia rekurencyjnie właściciela /opt/homebrew."
fi

packages=(colima docker docker-compose)
missing=()
for package in "${packages[@]}"; do
  if ! brew list --formula "${package}" >/dev/null 2>&1; then
    missing+=("${package}")
  fi
done

if (( ${#missing[@]} > 0 )); then
  blue "Instaluję: ${missing[*]}…"
  if ! brew install "${missing[@]}"; then
    fail "Homebrew nie zainstalował wymaganych programów. Uruchom „brew doctor”; nie używaj chown -R na całym /opt/homebrew."
  fi
else
  green "Wszystkie wymagane programy są już zainstalowane."
fi

require_command colima
require_command docker

# Homebrew instaluje Compose jako wtyczkę poza domyślną ścieżką Docker CLI.
# Prywatny link w katalogu użytkownika nie nadpisuje ~/.docker/config.json.
if ! docker compose version >/dev/null 2>&1; then
  compose_source="$(brew --prefix)/lib/docker/cli-plugins/docker-compose"
  compose_target="${HOME}/.docker/cli-plugins/docker-compose"
  [[ -x "${compose_source}" ]] || fail "nie znaleziono wtyczki Docker Compose po instalacji."
  mkdir -p "${HOME}/.docker/cli-plugins"
  if [[ -L "${compose_target}" ]]; then
    ln -sfn "${compose_source}" "${compose_target}"
  elif [[ ! -e "${compose_target}" ]]; then
    ln -s "${compose_source}" "${compose_target}"
  elif [[ ! -x "${compose_target}" ]]; then
    fail "${compose_target} istnieje i nie jest działającą wtyczką. Przenieś ten jeden plik w bezpieczne miejsce i uruchom instalator ponownie."
  fi
fi

if ! docker compose version >/dev/null 2>&1; then
  fail "Docker Compose nie jest dostępny. Istniejąca wtyczka w ~/.docker/cli-plugins może wymagać sprawdzenia."
fi

green "Wymagane programy są gotowe."
printf '%s\n' "Teraz uruchom dwuklikiem: 02-uruchom-silnik.command"
pause_at_end
