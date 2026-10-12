#!/bin/bash

# Owns one marked block at the end of ~/.config/hypr/monitors.lua.
#   monitors-lua.sh write < lines   merge the hl.monitor lines on stdin into the block
#                                   (same output replaces, others are kept)
#   monitors-lua.sh remove          delete the block
#   monitors-lua.sh read            print the block body
# Everything outside the markers is left byte-for-byte intact.

set -euo pipefail

file="${MONITORS_LUA:-$HOME/.config/hypr/monitors.lua}"
begin="-- BEGIN io.github.fluffet.display (managed by the Display panel, do not edit)"
end="-- END io.github.fluffet.display"

without_block() {
  [[ -f $file ]] || return 0
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { skipping = 1; next }
    $0 == end { skipping = 0; next }
    !skipping
  ' "$file"
}

block() {
  [[ -f $file ]] || return 0
  awk -v begin="$begin" -v end="$end" '
    $0 == begin { inside = 1; next }
    $0 == end { inside = 0 }
    inside
  ' "$file"
}

# Saved lines for displays that are not in the new lines, e.g. a projector
# that is unplugged right now. Lines match on their output = "..." field.
kept_lines() {
  awk '
    function output(line) {
      return match(line, /output = "([^"\\]|\\.)*"/) ? substr(line, RSTART, RLENGTH) : line
    }
    NR == FNR { if (NF) fresh[output($0)] = 1; next }
    NF && !(output($0) in fresh)
  ' <(printf '%s\n' "$1") <(block)
}

case "${1:-}" in
read)
  block
  ;;
write)
  body="$(cat)"
  kept="$(kept_lines "$body")"
  [[ -n $kept ]] && body="$body"$'\n'"$kept"
  tmp="$(mktemp "$file.XXXXXX")"
  {
    without_block | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'
    printf '\n%s\n%s\n%s\n' "$begin" "$body" "$end"
  } >"$tmp"
  mv "$tmp" "$file"
  ;;
remove)
  [[ -f $file ]] || exit 0
  tmp="$(mktemp "$file.XXXXXX")"
  without_block | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' >"$tmp"
  mv "$tmp" "$file"
  ;;
*)
  echo "usage: monitors-lua.sh read|write|remove" >&2
  exit 1
  ;;
esac
