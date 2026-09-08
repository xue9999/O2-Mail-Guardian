#!/bin/bash

set -Eeuo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
SWIFT_ARGS=(test --package-path "${PROJECT_DIR}/macos")
DEVELOPER_FRAMEWORKS="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

# Testuje również prawdziwy most Process -> JSON używany przez GUI, ale wyłącznie
# przeciw lokalnej atrapie bez dostępu do poczty, Keychain i usług systemowych.
export GUARDIAN_BIN="${PROJECT_DIR}/scripts/mock-gui-backend.sh"
export GUARDIAN_MOCK_SCENARIO=healthy
export GUARDIAN_MOCK_STATE="${TMPDIR:-/tmp}/o2-mail-guardian-swift-test.$$.state"
trap '/bin/rm -f -- "${GUARDIAN_MOCK_STATE}"' EXIT

# Pełny Xcode konfiguruje framework testowy sam. Samodzielne Command Line
# Tools 26 zawierają go, lecz nie dodają automatycznie ścieżki do SwiftPM.
if [[ ! -d /Applications/Xcode.app ]] && [[ -d "${DEVELOPER_FRAMEWORKS}/Testing.framework" ]]; then
  SWIFT_ARGS+=(
    -Xswiftc -F -Xswiftc "${DEVELOPER_FRAMEWORKS}"
    -Xlinker -F -Xlinker "${DEVELOPER_FRAMEWORKS}"
    -Xlinker -rpath -Xlinker "${DEVELOPER_FRAMEWORKS}"
  )
fi

/usr/bin/swift "${SWIFT_ARGS[@]}"
