#!/usr/bin/env bash
# Cornerstone bar-widget state probe. Prints exactly one line:
#   idle | recording | processing | error | nokey
set -u
status_file="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-dictation-cornerstone/status"
pid_file="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-dictation-cornerstone/record.pid"
key_file="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/dictation-cornerstone/api_key"

# "nokey" only matters when the Mistral engine is selected; local engines
# record fine without a key.
cfg_file="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/dictation-cornerstone/config.json"
if [[ ! -s $key_file ]] && [[ -z ${MISTRAL_API_KEY:-} ]] && grep -q '"stt_engine"[[:space:]]*:[[:space:]]*"mistral"' "$cfg_file" 2>/dev/null; then
  echo nokey
  exit 0
fi

if [[ -f $pid_file ]]; then
  pid=$(cat "$pid_file" 2>/dev/null || true)
  if [[ -n ${pid:-} ]] && kill -0 "$pid" 2>/dev/null; then
    echo recording
    exit 0
  fi
fi

if [[ -f $status_file ]]; then
  s=$(tr -d ' \t\r\n' <"$status_file")
  # A run that died mid-way would leave "processing" forever; expire it.
  if [[ $s == processing ]] && (( $(date +%s) - $(stat -c %Y "$status_file") > 300 )); then s=idle; fi
  case "$s" in
    idle|recording|processing|error|nokey) echo "$s" ;;
    *) echo idle ;;
  esac
  exit 0
fi

echo idle
