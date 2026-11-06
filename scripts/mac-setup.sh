#!/usr/bin/env bash
# Prepares a fresh Mac (e.g. an Amp Mac satellite) to build and verify Vaasi.
# Idempotent: safe to run on every new satellite before the first build.
set -euo pipefail
cd "$(dirname "$0")/.."

step() { printf '[mac-setup] %s\n' "$1"; }

if ! command -v xcodebuild >/dev/null 2>&1; then
  step "ERROR: Xcode is not installed (need Xcode 26+ for the macOS 26.0 deployment target)" >&2
  exit 1
fi
step "Xcode $(xcodebuild -version | head -1 | awk '{print $2}')"

# XcodeGen generates Vaasi.xcodeproj from project.yml. scripts/verify.sh runs
# it on every verification, but installing it here keeps that first run fast.
if ! command -v xcodegen >/dev/null 2>&1; then
  step "Installing xcodegen via Homebrew"
  brew install xcodegen
else
  step "xcodegen already present: $(xcodegen --version)"
fi

# The generated project is committed, so this only fills a gap if it is absent.
[ -d Vaasi.xcodeproj ] || xcodegen generate

step "Mac ready. Build and test with scripts/verify.sh --no-ui."
