#!/usr/bin/env bash
# Run every quality gate for the project in one shot.
#
# Backend:  TypeScript type-check + the four phase verify scripts.
# Mobile:   flutter analyze + flutter test (skipped with --no-mobile).
#
# Exits non-zero on the first failure. Used in CI and before demos.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/backend"
MOBILE="$ROOT/mobile"

# Colors so the prof can see green/red at a glance during the demo.
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

skip_mobile=false
for arg in "$@"; do
  case "$arg" in
    --no-mobile) skip_mobile=true ;;
    -h|--help)
      echo "usage: $0 [--no-mobile]"
      exit 0
      ;;
  esac
done

step() {
  printf "\n${YELLOW}▶ %s${RESET}\n" "$1"
}

ok() {
  printf "${GREEN}✓ %s${RESET}\n" "$1"
}

fail() {
  printf "${RED}✗ %s${RESET}\n" "$1" >&2
  exit 1
}

# --- backend -----------------------------------------------------------------

cd "$BACKEND"

step "backend: tsc --noEmit"
npx --no-install tsc --noEmit
ok "tsc clean"

# Phase verify scripts. Each prints its own "n/n asserts" line and exits 0 on
# success — we just need to make sure they all do.
for script in scripts/verify-phase3-math.ts \
              scripts/verify-phase4-ocr.ts \
              scripts/verify-phase4-llm.ts \
              scripts/verify-phase5-geo.ts \
              scripts/verify-phase6-cross-update.ts; do
  step "backend: $script"
  npx --no-install tsx "$script"
  ok "$(basename "$script") passed"
done

# --- mobile ------------------------------------------------------------------

if [ "$skip_mobile" = true ]; then
  printf "\n${YELLOW}skipping mobile checks (--no-mobile)${RESET}\n"
else
  cd "$MOBILE"

  step "mobile: flutter analyze"
  flutter analyze
  ok "flutter analyze clean"

  step "mobile: flutter test"
  flutter test
  ok "flutter tests passed"
fi

# --- summary -----------------------------------------------------------------

printf "\n${GREEN}All checks passed.${RESET}\n"
