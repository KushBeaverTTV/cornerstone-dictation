#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$DIR/cornerstone-status.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

export XDG_STATE_HOME="$TMP/state"
export XDG_CONFIG_HOME="$TMP/config"
unset MISTRAL_API_KEY
mkdir -p "$XDG_STATE_HOME/omarchy-dictation-cornerstone" "$XDG_CONFIG_HOME/omarchy/dictation-cornerstone"

assert_eq() {
  local got="$1" want="$2" name="$3"
  if [[ "$got" != "$want" ]]; then
    printf 'FAIL %s: got %q, want %q\n' "$name" "$got" "$want" >&2
    exit 1
  fi
}

assert_eq "$(bash "$SCRIPT")" "idle" "default idle"

echo "processing" > "$XDG_STATE_HOME/omarchy-dictation-cornerstone/status"
assert_eq "$(bash "$SCRIPT")" "processing" "processing status"

echo "error" > "$XDG_STATE_HOME/omarchy-dictation-cornerstone/status"
assert_eq "$(bash "$SCRIPT")" "error" "error status"

echo "garbage" > "$XDG_STATE_HOME/omarchy-dictation-cornerstone/status"
assert_eq "$(bash "$SCRIPT")" "idle" "unknown status falls back to idle"

echo "$$" > "$XDG_STATE_HOME/omarchy-dictation-cornerstone/record.pid"
assert_eq "$(bash "$SCRIPT")" "recording" "live pid reports recording"
rm -f "$XDG_STATE_HOME/omarchy-dictation-cornerstone/record.pid"

printf '{"stt_engine":"mistral"}\n' > "$XDG_CONFIG_HOME/omarchy/dictation-cornerstone/config.json"
assert_eq "$(bash "$SCRIPT")" "nokey" "mistral without key reports nokey"

echo "secret" > "$XDG_CONFIG_HOME/omarchy/dictation-cornerstone/api_key"
assert_eq "$(bash "$SCRIPT")" "idle" "mistral with key reports status"

echo "PASS cornerstone.panel status tests"
