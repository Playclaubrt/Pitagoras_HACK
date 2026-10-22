#!/usr/bin/env bash
set -eu

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  SOURCE_DIR="$(CDPATH= cd -P -- "$(dirname -- "$SOURCE")" && pwd)"
  LINK="$(readlink "$SOURCE")"
  case "$LINK" in /*) SOURCE="$LINK" ;; *) SOURCE="$SOURCE_DIR/$LINK" ;; esac
done
PROJECT_DIR="$(CDPATH= cd -- "$(dirname -- "$SOURCE")" && pwd)"
OS="$(uname -s 2>/dev/null || echo unknown)"
need_sudo=0
run_root() {
  if [ "$(id -u)" -eq 0 ]; then "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else echo "This installer needs root privileges. Install sudo or run it as root." >&2; return 1
  fi
}

case "$OS" in
  Linux*)
    if [ -n "${PREFIX:-}" ] && command -v pkg >/dev/null 2>&1; then
      echo "Detected Termux. Installing packages with pkg..."
      pkg update -y
      pkg install -y bash curl git python postgresql
    elif command -v apt-get >/dev/null 2>&1; then
      echo "Detected Debian/Ubuntu. Installing packages with apt..."
      run_root apt-get update
      run_root apt-get install -y bash curl git python3 postgresql-client
    elif command -v dnf >/dev/null 2>&1; then
      echo "Detected Fedora/RHEL. Installing packages with dnf..."
      run_root dnf install -y bash curl git python3 postgresql
    elif command -v yum >/dev/null 2>&1; then
      echo "Detected RHEL/CentOS. Installing packages with yum..."
      run_root yum install -y bash curl git python3 postgresql
    elif command -v pacman >/dev/null 2>&1; then
      echo "Detected Arch Linux. Installing packages with pacman..."
      run_root pacman -Sy --needed --noconfirm bash curl git python postgresql
    elif command -v zypper >/dev/null 2>&1; then
      echo "Detected openSUSE. Installing packages with zypper..."
      run_root zypper --non-interactive install bash curl git python3 postgresql
    else
      echo "Linux detected, but no supported package manager (apt, dnf, yum, pacman, zypper, pkg)." >&2
      exit 1
    fi
    ;;
  Darwin*)
    echo "Detected macOS."
    if ! command -v brew >/dev/null 2>&1; then
      echo "Install Homebrew from https://brew.sh, then run this installer again." >&2
      exit 1
    fi
    brew install bash curl git python postgresql@16
    ;;
  MINGW*|MSYS*|CYGWIN*)
    echo "Detected Windows shell (Git Bash/MSYS/Cygwin)."
    if command -v winget >/dev/null 2>&1; then
      winget install --id Git.Git -e --accept-package-agreements --accept-source-agreements
      winget install --id Python.Python.3.12 -e --accept-package-agreements --accept-source-agreements
      winget install --id PostgreSQL.PostgreSQL -e --accept-package-agreements --accept-source-agreements
      echo "curl and Bash are provided by Git for Windows. Restart the terminal after installation."
    elif command -v choco >/dev/null 2>&1; then
      choco install -y git python postgresql
    else
      echo "Install Git for Windows, Python 3, and PostgreSQL (psql), then rerun this installer." >&2
      echo "winget is recommended: winget install Git.Git; winget install Python.Python.3.12; winget install PostgreSQL.PostgreSQL" >&2
      exit 1
    fi
    ;;
  *)
    echo "Unsupported OS: $OS. Install Bash, curl, Git, Python 3, and PostgreSQL client manually." >&2
    exit 1
    ;;
esac

# Ensure the user's private Neon credentials file exists without overwriting it.
if [ ! -f "$PROJECT_DIR/.env" ]; then
  cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
  chmod 600 "$PROJECT_DIR/.env" 2>/dev/null || true
  echo "Created .env from .env.example. Edit .env and set NEON_DATABASE_URL before launching."
else
  echo "Keeping existing .env unchanged."
fi

# Create a convenient launcher link where possible.
if [ -n "${PREFIX:-}" ] && [ -d "$PREFIX/bin" ]; then
  BIN_DIR="$PREFIX/bin"
else
  BIN_DIR="$HOME/.local/bin"
  mkdir -p "$BIN_DIR"
fi
ln -sf "$PROJECT_DIR/pitagocript" "$BIN_DIR/pitagocript"
echo "Installed launcher: $BIN_DIR/pitagocript"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "Add $BIN_DIR to PATH, then reopen the terminal." ;; esac

echo "Setup complete. Confirm .env has your Neon URI, then run pitagocript."
