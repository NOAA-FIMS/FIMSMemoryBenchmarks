#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$HOME/.R"
MAKEVARS="$HOME/.R/Makevars"

touch "$MAKEVARS"

add_line_if_missing() {
  local line="$1"
  if ! grep -Fqx "$line" "$MAKEVARS"; then
    printf '%s\n' "$line" >> "$MAKEVARS"
  fi
}

add_line_if_missing "PKG_CXXFLAGS += -g -O0 -fno-omit-frame-pointer -fvisibility=default"
add_line_if_missing "PKG_STRIP = true"

echo "Configured $MAKEVARS for debug builds."
