#!/usr/bin/env bash
# Builds Vaasi, runs every test layer against the real app, and checks that each
# feature in features.json is proven by passing tests.
#
#   scripts/verify.sh                   everything
#   scripts/verify.sh --no-ui           skip UI tests (they take over the pointer)
#   scripts/verify.sh --only prompter.cues,voice.activity
#                                       only the tests behind those features
set -euo pipefail
cd "$(dirname "$0")/.."

ONLY=""
RUN_UI=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --only) ONLY="$2"; shift 2 ;;
    --no-ui) RUN_UI=0; shift ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

RUN="verification/runs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$RUN"
DERIVED="build/DerivedData"
DEST="platform=macOS"
echo "▸ Run folder: $RUN"

# Tests to run, grouped by layer, when --only is given.
selected() {
  python3 -I - "$1" "$ONLY" <<'EOF'
import json, sys
layer, only = sys.argv[1], set(sys.argv[2].split(","))
tests = set()
for f in json.load(open("features.json"))["features"]:
    if f["id"] in only:
        tests.update(t for t in f.get("tests", []) if t.startswith(layer + "/"))
print(" ".join(sorted(tests)))
EOF
}

echo "▸ Generating project"
xcodegen generate --quiet

echo "▸ Core package tests"
CORE_FILTER=()
if [[ -n "$ONLY" ]]; then
  for t in $(selected VaasiCoreTests); do
    name="${t#VaasiCoreTests/}"; CORE_FILTER+=(--filter "${name%%(*}")
  done
fi
if [[ -z "$ONLY" || ${#CORE_FILTER[@]} -gt 0 ]]; then
  (cd Packages/VaasiKit && swift test ${CORE_FILTER[@]+"${CORE_FILTER[@]}"} --xunit-output "../../$RUN/core.xml" >"../../$RUN/core.log" 2>&1) \
    || echo "  core tests reported failures (see $RUN/core.log)"
fi

echo "▸ Building app and test bundles"
xcodebuild -project Vaasi.xcodeproj -scheme Vaasi -destination "$DEST" -derivedDataPath "$DERIVED" \
  build-for-testing >"$RUN/build.log" 2>&1 || { tail -40 "$RUN/build.log"; exit 1; }

run_xcode_tests() {
  local bundle="$1" args=()
  if [[ -n "$ONLY" ]]; then
    for t in $(selected "$bundle"); do args+=("-only-testing:$t"); done
    [[ ${#args[@]} -eq 0 ]] && return 0
  else
    args=("-only-testing:$bundle")
  fi
  echo "▸ $bundle"
  xcodebuild -project Vaasi.xcodeproj -scheme Vaasi -destination "$DEST" -derivedDataPath "$DERIVED" \
    test-without-building "${args[@]}" -resultBundlePath "$RUN/$bundle.xcresult" >"$RUN/$bundle.log" 2>&1 \
    || echo "  $bundle reported failures (see $RUN/$bundle.log)"
}

run_xcode_tests VaasiTests
if [[ $RUN_UI -eq 1 ]]; then
  run_xcode_tests VaasiUITests
  if [[ -d "$RUN/VaasiUITests.xcresult" ]]; then
    xcrun xcresulttool export attachments --path "$RUN/VaasiUITests.xcresult" --output-path "$RUN/screenshots" >/dev/null 2>&1 || true
  fi
fi

echo "▸ Static checks"
APP="$DERIVED/Build/Products/Debug/Vaasi.app"
ENTITLEMENTS="$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)"
if [[ "$ENTITLEMENTS" == *"com.apple.security.app-sandbox"* && "$ENTITLEMENTS" != *"network.client"* && "$ENTITLEMENTS" != *"network.server"* ]]; then
  NET="Passed"
else
  NET="Failed"
fi
printf '{"static/no-network-entitlement": "%s"}\n' "$NET" >"$RUN/static.json"

echo "▸ Feature report"
if [[ -n "$ONLY" ]]; then
  python3 -I scripts/feature_report.py "$RUN" --only "$ONLY"
else
  python3 -I scripts/feature_report.py "$RUN"
fi
