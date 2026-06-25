#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/sczhou/ProPainter.git"
INSTALL_DIR="${1:-$HOME/.watermark-studio/backends/ProPainter}"
CREATE_VENV="${CREATE_VENV:-1}"
INSTALL_REQUIREMENTS="${INSTALL_REQUIREMENTS:-0}"

usage() {
  cat <<'USAGE'
Usage:
  scripts/bootstrap_propainter.sh [install-dir]

Environment:
  CREATE_VENV=1|0             Create .venv inside the ProPainter checkout. Default: 1.
  INSTALL_REQUIREMENTS=1|0    Run pip install -r requirements.txt when present. Default: 0.

Examples:
  scripts/bootstrap_propainter.sh
  scripts/bootstrap_propainter.sh ~/Tools/ProPainter
  INSTALL_REQUIREMENTS=1 scripts/bootstrap_propainter.sh ~/Tools/ProPainter
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  echo "error: git is required." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "error: python3 is required." >&2
  exit 1
fi

mkdir -p "$(dirname "$INSTALL_DIR")"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating ProPainter at: $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only
elif [[ -e "$INSTALL_DIR" ]]; then
  echo "error: install path exists but is not a git checkout: $INSTALL_DIR" >&2
  exit 1
else
  echo "Cloning ProPainter into: $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

if [[ "$CREATE_VENV" == "1" ]]; then
  if [[ ! -d "$INSTALL_DIR/.venv" ]]; then
    echo "Creating Python virtual environment: $INSTALL_DIR/.venv"
    python3 -m venv "$INSTALL_DIR/.venv"
  fi

  if [[ "$INSTALL_REQUIREMENTS" == "1" ]]; then
    if [[ -f "$INSTALL_DIR/requirements.txt" ]]; then
      echo "Installing ProPainter requirements into .venv"
      "$INSTALL_DIR/.venv/bin/python" -m pip install --upgrade pip
      "$INSTALL_DIR/.venv/bin/python" -m pip install -r "$INSTALL_DIR/requirements.txt"
    else
      echo "warning: requirements.txt not found; skipping dependency install." >&2
    fi
  fi
fi

cat <<EOF

ProPainter checkout is ready.

ProPainter path:
  $INSTALL_DIR

Python executable:
  $INSTALL_DIR/.venv/bin/python

Next check:
  watermark-studio doctor --python "$INSTALL_DIR/.venv/bin/python" --propainter-dir "$INSTALL_DIR"

If you manage ProPainter with Conda or another environment, use that Python executable instead.
EOF
