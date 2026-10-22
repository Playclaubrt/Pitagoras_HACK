#!/usr/bin/env bash
set -eu
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  SOURCE_DIR="$(CDPATH= cd -P -- "$(dirname -- "$SOURCE")" && pwd)"
  LINK="$(readlink "$SOURCE")"
  case "$LINK" in /*) SOURCE="$LINK" ;; *) SOURCE="$SOURCE_DIR/$LINK" ;; esac
done
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$SOURCE")" && pwd)"
if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/bin" ]; then
  BIN_DIR="$PREFIX/bin"
else
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
fi
ln -sf "$PROJECT_DIR/pitagocript" "$BIN_DIR/pitagocript"
printf 'Installed pitagocript in %s\n' "$BIN_DIR"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) printf 'Add this to your shell profile if needed: export PATH="%s:$PATH"\n' "$BIN_DIR" ;; esac
