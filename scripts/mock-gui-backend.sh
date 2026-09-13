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
if [[ "${scenario}" == "active" ]]; then mode="active"; fi
if [[ "${scenario}" == "manual" ]]; then automation="off"; fi

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
  exit 0
}

read_request() {
  request="$(dd bs=65537 count=1 2>/dev/null || true)"
}

command="${1:-}"
shift || true
case "${command}" in
  snapshot)
    if [[ "${scenario}" == "offline" ]]; then
      failure RSPAMD_UNAVAILABLE "Lokalny silnik nie odpowiada." "Sprawdź i napraw lokalną ochronę."
    fi
    if [[ "${configured}" != "true" ]]; then
      success '{"configured":false,"health":"unconfigured","health_label":"Wymaga konfiguracji","recommendation":"Dokończ pierwszą konfigurację.","automation":"off","mode":"protect","purge_enabled":false,"summary":{},"trained_spam":0,"trained_ham":0,"required_spam":200,"required_ham":200,"first_dry_run":false,"app_autostart":false,"version":"0.4.0-test"}'
      exit 0
    fi
    health="healthy"
    health_label="Wszystko działa"
    recommendation="Nie musisz nic robić."
    if [[ "${automation}" == "off" ]]; then
      health="manual"; health_label="Tryb ręczny"; recommendation="Włącz automatyczne sprawdzanie albo uruchamiaj je ręcznie."
    elif [[ "${scenario}" == "attention" ]]; then
      health="attention"
      health_label="Wymaga uwagi"; recommendation="Sprawdź teraz skrzynkę albo uruchom Napraw."
    elif [[ "${scenario}" == "critical" ]]; then
      health="critical"
      health_label="Nie działa"; recommendation="Uruchom Napraw; automat nie zakończył pracy od ponad 48 godzin."
    fi
    remaining=8
    ready=false
    quality=false
    if [[ "${scenario}" == "ready" || "${mode}" == "active" ]]; then remaining=0; ready=true; quality=true; fi
    progress_message="Oznacz pomyłki w folderach nauki, aby potwierdzić jakość decyzji."
    if [[ "${ready}" == "true" ]]; then progress_message="Warunki spełnione. Możesz włączyć porządkowanie Odebranych."; fi
    current_date="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    pending=0
    if [[ "${scenario}" == "attention" ]]; then pending=1; fi
    quality_checks='[{"id":"sample","title":"Potwierdzony spam","detail":"Wiadomości oznaczone przez Ciebie jako spam w tym okresie: 10. Potrzebna jest co najmniej jedna.","passed":true},{"id":"accuracy","title":"Trafne rozpoznanie spamu","detail":"Wymagane co najmniej 90% zgodności wcześniejszych decyzji z Twoimi potwierdzeniami.","passed":'"${quality}"'},{"id":"important","title":"Ważne wiadomości bez błędnego oznaczenia jako spam","detail":"Potwierdzone przez Ciebie pomyłki: 0. Wymagane zero w tym okresie obserwacji.","passed":true},{"id":"rescues","title":"Spam bez błędnego uznania za ważną wiadomość","detail":"Potwierdzone przez Ciebie pomyłki: 0. Wymagane zero w tym okresie obserwacji.","passed":true},{"id":"history","title":"Znana wcześniejsza decyzja","detail":"Potwierdzony spam bez wcześniejszej decyzji: 0. Wymagane zero.","passed":true}]'
    success "{\"protection\":{\"quality_checks\":${quality_checks},\"required_days\":14,\"remaining_days\":${remaining},\"period_complete\":${ready},\"quality_ready\":${quality},\"ready\":${ready},\"message\":\"${progress_message}\"},\"configured\":true,\"health\":\"${health}\",\"health_label\":\"${health_label}\",\"recommendation\":\"${recommendation}\",\"automation\":\"${automation}\",\"mode\":\"${mode}\",\"purge_enabled\":${purge},\"last_attempt\":\"${current_date}\",\"last_success\":\"${current_date}\",\"stage\":\"complete\",\"summary\":{\"runs\":6,\"scanned\":84,\"kept\":71,\"rescued\":2,\"quarantined\":8,\"review\":3,\"errors\":0,\"waiting_quarantine\":18,\"waiting_review\":4,\"pending_moves\":${pending}},\"trained_spam\":143,\"trained_ham\":126,\"required_spam\":200,\"required_ham\":200,\"first_dry_run\":${first_dry_run},\"app_autostart\":${app_autostart},\"version\":\"0.4.0-test\"}"
    ;;
  run)
    if [[ "${1:-}" == "dry-run" && "${configured}" == "true" ]]; then
      first_dry_run="true"
      save_state
    fi
    dry=false
    if [[ "${1:-}" == "dry-run" ]]; then dry=true; fi
    success "{\"completed\":true,\"summary\":{\"dry_run\":${dry},\"scanned\":24,\"kept\":18,\"rescued\":0,\"quarantined\":0,\"review\":6,\"errors\":0}}"
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
        if [[ "${scenario}" == "archive-error" ]]; then
          failure ARCHIVE "Nie udało się odczytać kopii." "Spróbuj ponownie."
          exit 0
        fi
        page="${2:-1}"
        category="${3:-all}"
        if [[ $# -eq 5 ]]; then
          matches=""
          if [[ "${scenario}" != "empty" ]]; then
            while IFS='|' read -r copy_id copy_date copy_status copy_verdict; do
              [[ "${category}" == "all" || "${category}" == "${copy_status}" ]] || continue
              [[ "${copy_date}" < "$4" || ! "${copy_date}" < "$5" ]] && continue
              [[ -z "${matches}" ]] || matches+=","
              matches+="{\"id\":${copy_id},\"date\":\"${copy_date}\",\"verdict\":\"${copy_verdict}\",\"status\":\"${copy_status}\"}"
            done <<'COPIES'
104|2026-08-21T18:42:00Z|quarantined|spam
103|2026-08-20T09:15:00Z|quarantined|spam
102|2026-08-19T13:07:00Z|review|uncertain
101|2026-08-18T07:21:00Z|quarantined|spam
COPIES
          fi
          [[ "${page}" == "1" ]] || matches=""
          success "{\"page\":${page},\"items\":[${matches}],\"has_next\":false}"
          exit 0
        fi
        if [[ "${scenario}" == "empty" || "${category}" == "restored" ]]; then
          success '{"page":1,"items":[],"has_next":false}'
          exit 0
        fi
        if [[ "${category}" == "review" ]]; then
          success '{"page":1,"items":[{"id":102,"date":"2026-08-19T13:07:00Z","verdict":"uncertain","status":"review"}],"has_next":false}'
          exit 0
        fi
        if [[ "${category}" == "quarantined" ]]; then
          success '{"page":1,"items":[{"id":104,"date":"2026-08-21T18:42:00Z","verdict":"spam","status":"quarantined"}],"has_next":false}'
          exit 0
        fi
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
