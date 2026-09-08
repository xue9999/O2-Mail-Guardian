#!/bin/bash

set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
TEST_ROOT="$(/usr/bin/mktemp -d /tmp/o2-guardian-release-test.XXXXXX)"
PACKAGE_TEST_HOME="$(/usr/bin/mktemp -d /tmp/o2-guardian-installer-test.XXXXXX)"
DIST_DIR="${TEST_ROOT}/dist"
EXTRACT_DIR="${TEST_ROOT}/extract"
cleanup() {
  case "${TEST_ROOT}" in
    /tmp/o2-guardian-release-test.*) /bin/rm -rf -- "${TEST_ROOT}" ;;
  esac
  case "${PACKAGE_TEST_HOME}" in
    /tmp/o2-guardian-installer-test.*) /bin/rm -rf -- "${PACKAGE_TEST_HOME}" ;;
  esac
}
trap cleanup EXIT

GUARDIAN_DIST_DIR="${DIST_DIR}" /bin/bash "${PROJECT_DIR}/scripts/package-release.sh" >/dev/null
archive="$(find "${DIST_DIR}" -maxdepth 1 -type f -name 'O2-Mail-Guardian-*.zip' -print -quit)"
[[ -n "${archive}" ]]
if /usr/bin/unzip -Z1 "${archive}" | /usr/bin/grep -Eq '(^|/)__MACOSX/|/\._'; then
  printf 'Paczka zawiera widoczne metadane macOS zamiast czystego układu.\n' >&2
  exit 1
fi
/bin/mkdir -p "${EXTRACT_DIR}"
/usr/bin/ditto -x -k "${archive}" "${EXTRACT_DIR}"
package_root="$(find "${EXTRACT_DIR}" -mindepth 1 -maxdepth 1 -type d -name 'O2 Mail Guardian *' -print -quit)"
[[ -n "${package_root}" ]]

visible="$(find "${package_root}" -mindepth 1 -maxdepth 1 ! -name '.*' -print | /usr/bin/sed "s#${package_root}/##" | LC_ALL=C /usr/bin/sort)"
expected=$'Install.command\nLICENSE\nZACZNIJ-TUTAJ.txt'
[[ "${visible}" == "${expected}" ]] || {
  printf 'Gotowa paczka pokazuje nieoczekiwane pliki:\n%s\n' "${visible}" >&2
  exit 1
}

[[ -x "${package_root}/Install.command" ]]
[[ -f "${package_root}/.payload/scripts/install-core.sh" ]]
[[ -f "${package_root}/.payload/macos/Sources/O2MailGuardianApp/O2MailGuardianApp.swift" ]]
[[ -f "${package_root}/.payload/LICENSE" ]]
[[ ! -e "${package_root}/.payload/macos/Tests" ]]
/usr/bin/grep -Fq -- '--self-test' "${package_root}/.payload/scripts/install-core.sh"
/usr/bin/grep -Fq 'Control' "${package_root}/ZACZNIJ-TUTAJ.txt"
/usr/bin/grep -Fq 'osobnego hasła aplikacyjnego' "${package_root}/ZACZNIJ-TUTAJ.txt"
if find "${package_root}" \( -name .build -o -name .git -o -name bin -o -name '*.db' -o -name '*.log' \) -print -quit | /usr/bin/grep -q .; then
  printf 'Paczka zawiera lokalne artefakty albo dane robocze.\n' >&2
  exit 1
fi

cancel_output="$(printf 'N\n' | HOME="${TEST_ROOT}/home" GUARDIAN_SKIP_PAUSE=1 /bin/bash "${package_root}/Install.command" 2>&1)"
[[ "${cancel_output}" == *"niczego nie zmieniono"* ]]

HOME="${PACKAGE_TEST_HOME}" \
XDG_CONFIG_HOME="${PACKAGE_TEST_HOME}/config" \
GUARDIAN_INSTALL_SELF_TEST=1 \
/bin/bash "${package_root}/Install.command" >/dev/null

printf 'Prosta paczka wydania: OK\n'
