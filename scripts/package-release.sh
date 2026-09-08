#!/bin/bash

set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
VERSION="$(/usr/bin/tr -d '[:space:]' < "${PROJECT_DIR}/VERSION")"
DIST_DIR="${GUARDIAN_DIST_DIR:-${PROJECT_DIR}/dist}"
STAGE_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/o2-mail-guardian-package.XXXXXX")"
PACKAGE_ROOT="${STAGE_ROOT}/O2 Mail Guardian ${VERSION}"
PAYLOAD="${PACKAGE_ROOT}/.payload"
ARCHIVE_TMP="${STAGE_ROOT}/O2-Mail-Guardian-${VERSION}.zip"
ARCHIVE="${DIST_DIR}/O2-Mail-Guardian-${VERSION}.zip"

cleanup() {
  case "${STAGE_ROOT}" in
    "${TMPDIR:-/tmp}"/o2-mail-guardian-package.*|/tmp/o2-mail-guardian-package.*)
      /bin/rm -rf -- "${STAGE_ROOT}"
      ;;
  esac
}
trap cleanup EXIT

[[ "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]]
/bin/mkdir -p "${PAYLOAD}" "${DIST_DIR}"

/bin/cp "${PROJECT_DIR}/Install.command" "${PACKAGE_ROOT}/Install.command"
/bin/chmod 755 "${PACKAGE_ROOT}/Install.command"
/bin/cp "${PROJECT_DIR}/LICENSE" "${PACKAGE_ROOT}/LICENSE"

printf '%s\n' \
  'O2 MAIL GUARDIAN — ZACZNIJ TUTAJ' \
  '' \
  '1. Kliknij dwukrotnie Install.command.' \
  '2. Naciśnij Enter, aby rozpocząć.' \
  '3. Poczekaj, aż otworzy się aplikacja.' \
  '4. Przejdź trzy krótkie ekrany konfiguracji.' \
  '' \
  'Jeśli macOS zablokuje dwuklik: kliknij Install.command z klawiszem Control,' \
  'wybierz Otwórz, a potem ponownie Otwórz. Nie wyłączaj zabezpieczeń Maca.' \
  '' \
  'W aplikacji potrzebujesz osobnego hasła aplikacyjnego o2, nie zwykłego' \
  'hasła do poczty. Pierwszy ekran zawiera odnośnik do instrukcji o2.' \
  '' \
  'Nie otwieraj katalogu .payload — zawiera wyłącznie techniczne składniki instalatora.' \
  'Instalator nie pyta w Terminalu o hasło do poczty i nie włącza trwałego usuwania.' \
  > "${PACKAGE_ROOT}/ZACZNIJ-TUTAJ.txt"

for file in VERSION go.mod go.sum README.md LICENSE Guardian.command Uruchom-teraz.command Sprawdz-stan.command; do
  /bin/cp "${PROJECT_DIR}/${file}" "${PAYLOAD}/${file}"
done
for command_file in Guardian.command Uruchom-teraz.command Sprawdz-stan.command; do
  /bin/chmod 755 "${PAYLOAD}/${command_file}"
done
for directory in cmd internal deploy docs scripts; do
  /usr/bin/ditto --norsrc --noqtn "${PROJECT_DIR}/${directory}" "${PAYLOAD}/${directory}"
done

# SwiftPM potrzebuje wyłącznie tych źródeł. Celowo nie pakujemy .build,
# lokalnych artefaktów, logów, baz ani ustawień deweloperskich.
/bin/mkdir -p "${PAYLOAD}/macos"
for file in Package.swift Info.plist; do
  /bin/cp "${PROJECT_DIR}/macos/${file}" "${PAYLOAD}/macos/${file}"
done
/usr/bin/ditto --norsrc --noqtn "${PROJECT_DIR}/macos/Sources" "${PAYLOAD}/macos/Sources"

/usr/bin/ditto -c -k --norsrc --noqtn --keepParent "${PACKAGE_ROOT}" "${ARCHIVE_TMP}"
/bin/mv -f "${ARCHIVE_TMP}" "${ARCHIVE}"
/bin/chmod 644 "${ARCHIVE}"
printf 'Gotowa prosta paczka: %s\n' "${ARCHIVE}"
