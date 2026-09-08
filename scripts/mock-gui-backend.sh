#!/bin/bash

# Lokalny backend demonstracyjny do ręcznych testów SwiftUI.
# Nie łączy się z IMAP, Keychain, Rspamd ani launchd.
set -Eeuo pipefail

if [[ "${1:-}" != "api" ]]; then
  printf '%s\n' '{"protocol":1,"ok":false,"error":{"code":"MOCK_USAGE","severity":"error","message":"Atrapa obsługuje wyłącznie lokalne API GUI."}}'
  exit 1
fi
shift

scenario="${GUARDIAN_MOCK_SCENARIO:-healthy}"
state_file="${GUARDIAN_MOCK_STATE:-${TMPDIR:-/tmp}/o2-mail-guardian-gui-mock.state}"
automation="on"
app_autostart="true"
mode="protect"
purge="false"
configured="true"
first_dry_run="true"

if [[ "${scenario}" == "unconfigured" ]]; then
  configured="false"
  first_dry_run="false"
  automation="off"
  app_autostart="false"
fi

if [[ -f "${state_file}" ]]; then
  while IFS='=' read -r key value; do
    case "${key}" in
      automation) [[ "${value}" == "on" || "${value}" == "off" ]] && automation="${value}" ;;
      app_autostart) [[ "${value}" == "true" || "${value}" == "false" ]] && app_autostart="${value}" ;;
      mode) [[ "${value}" == "protect" || "${value}" == "active" ]] && mode="${value}" ;;
      purge) [[ "${value}" == "true" || "${value}" == "false" ]] && purge="${value}" ;;
      configured) [[ "${value}" == "true" || "${value}" == "false" ]] && configured="${value}" ;;
      first_dry_run) [[ "${value}" == "true" || "${value}" == "false" ]] && first_dry_run="${value}" ;;
    esac
  done < "${state_file}"
fi

save_state() {
  local temporary="${state_file}.$$"
  umask 077
  {
    printf 'automation=%s\n' "${automation}"
    printf 'app_autostart=%s\n' "${app_autostart}"
    printf 'mode=%s\n' "${mode}"
    printf 'purge=%s\n' "${purge}"
    printf 'configured=%s\n' "${configured}"
    printf 'first_dry_run=%s\n' "${first_dry_run}"
  } > "${temporary}"
  mv -f -- "${temporary}" "${state_file}"
}

success() {
  printf '{"protocol":1,"ok":true,"data":%s}\n' "$1"
}

failure() {
  printf '{"protocol":1,"ok":false,"error":{"code":"%s","severity":"attention","message":"%s","recovery":"%s"}}\n' "$1" "$2" "$3"
  exit 1
}

read_request() {
  request="$(dd bs=65537 count=1 2>/dev/null || true)"
}

command="${1:-}"
shift || true
case "${command}" in
  snapshot)
    if [[ "${configured}" != "true" ]]; then
      success '{"configured":false,"health":"unconfigured","health_label":"Wymaga konfiguracji","recommendation":"Dokończ pierwszą konfigurację.","automation":"off","mode":"protect","purge_enabled":false,"summary":{},"trained_spam":0,"trained_ham":0,"required_spam":200,"required_ham":200,"first_dry_run":false,"app_autostart":false,"version":"0.3.0-test"}'
      exit 0
    fi
    health="${scenario}"
    health_label="Wszystko działa"
    recommendation="Nie musisz nic robić."
    if [[ "${automation}" == "off" ]]; then
      health="manual"; health_label="Tryb ręczny"; recommendation="Włącz automatyczne sprawdzanie albo uruchamiaj je ręcznie."
    elif [[ "${scenario}" == "attention" ]]; then
      health_label="Wymaga uwagi"; recommendation="Sprawdź teraz skrzynkę albo uruchom Napraw."
    elif [[ "${scenario}" == "critical" ]]; then
      health_label="Nie działa"; recommendation="Uruchom Napraw; automat nie zakończył pracy od ponad 48 godzin."
    fi
    success "{\"configured\":true,\"health\":\"${health}\",\"health_label\":\"${health_label}\",\"recommendation\":\"${recommendation}\",\"automation\":\"${automation}\",\"mode\":\"${mode}\",\"purge_enabled\":${purge},\"last_attempt\":\"2026-08-22T12:34:00Z\",\"last_success\":\"2026-08-22T12:31:00Z\",\"stage\":\"complete\",\"summary\":{\"runs\":6,\"scanned\":84,\"kept\":71,\"rescued\":2,\"quarantined\":8,\"review\":3,\"errors\":0,\"waiting_quarantine\":18,\"waiting_review\":4,\"pending_moves\":1},\"trained_spam\":143,\"trained_ham\":126,\"required_spam\":200,\"required_ham\":200,\"first_dry_run\":${first_dry_run},\"app_autostart\":${app_autostart},\"version\":\"0.3.0-test\"}"
    ;;
  run)
    if [[ "${1:-}" == "dry-run" && "${configured}" == "true" ]]; then
      first_dry_run="true"
      save_state
    fi
    success '{"completed":true}'
    ;;
  repair|doctor)
    success '{"completed":true}'
    ;;
  diagnostics)
    success '{"path":"~/Desktop/O2-Mail-Guardian-diagnostyka-test.zip"}'
    ;;
  service)
    case "${1:-}" in enable) automation="on" ;; disable) automation="off" ;; *) failure MOCK_USAGE "Nieznana operacja usługi." "Użyj enable lub disable." ;; esac
    save_state
    success "{\"automation\":\"${automation}\"}"
    ;;
  app-autostart)
    case "${1:-}" in enable) app_autostart="true" ;; disable) app_autostart="false" ;; *) failure MOCK_USAGE "Nieznana operacja autostartu." "Użyj enable lub disable." ;; esac
    save_state
    success "{\"app_autostart\":${app_autostart}}"
    ;;
  archive)
    case "${1:-}" in
      list)
        page="${2:-1}"
        if [[ "${page}" == "1" ]]; then
          success '{"page":1,"items":[{"id":104,"date":"2026-08-21T18:42:00Z","verdict":"spam","status":"quarantined"},{"id":103,"date":"2026-08-20T09:15:00Z","verdict":"spam","status":"quarantined"},{"id":102,"date":"2026-08-19T13:07:00Z","verdict":"uncertain","status":"review"}],"has_next":true}'
        else
          success "{\"page\":${page},\"items\":[{\"id\":101,\"date\":\"2026-08-18T07:21:00Z\",\"verdict\":\"spam\",\"status\":\"quarantined\"}],\"has_next\":false}"
        fi
        ;;
      preview)
        success '{"from":"nadawca@example.test","subject":"Przykładowy oczyszczony temat","date":"2026-08-21 18:42"}'
        ;;
      restore)
        success '{"restored":true,"already_present":false}'
        ;;
      *) failure MOCK_USAGE "Nieznana operacja archiwum." "Użyj list, preview lub restore." ;;
    esac
    ;;
  mode)
    read_request
    if [[ "${request}" == *'"value":"active"'* ]]; then mode="active"; else mode="protect"; fi
    save_state
    success '{}'
    ;;
  purge)
    read_request
    if [[ "${request}" == *'"value":"enable"'* ]]; then purge="true"; else purge="false"; fi
    save_state
    success '{}'
    ;;
  setup)
    read_request
    case "${1:-}" in
      probe) success '{"detected_spam":"Spam","folders":["Spam","Junk","Niechciane"],"safe_move":true}' ;;
      commit)
        if [[ "${request}" != *'"accept_existing_training":true'* ]]; then
          failure MOCK_CONFIRMATION "Nie potwierdzono folderów nauki." "Wróć do wykrytych ustawień i użyj przycisku potwierdzenia."
        fi
        configured="true"
        first_dry_run="false"
        automation="off"
        mode="protect"
        purge="false"
        save_state
        success '{"configured":true,"spam_folder":"Spam","first_dry_run_required":true}'
        ;;
      *) failure MOCK_USAGE "Nieznany krok konfiguracji." "Użyj probe lub commit." ;;
    esac
    ;;
  *) failure MOCK_USAGE "Nieznane polecenie atrapy." "Sprawdź scenariusz testowy." ;;
esac
