#!/usr/bin/env bash
# build.sh — compile the reddit CLI into a standalone single binary.
#
#   ./build.sh                 # build into dist/reddit
#   ./build.sh --install       # build + install to ~/.local/bin/reddit
#
# The `reddit` source file is stdlib-only Python; PyInstaller freezes it with
# an embedded interpreter so the result runs with no Python installed.
# Output is a Mach-O executable for the BUILD machine's OS/arch
# (macOS arm64 here). Build on the target platform per binary.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/reddit"
VENV="${BUILD_VENV:-/tmp/any2cli-reddit-build-venv}"

echo "==> preparing isolated build venv (does not touch user site-packages)"
if [ ! -x "$VENV/bin/pyinstaller" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip pyinstaller
fi

echo "==> building single-file binary"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$SRC" "$WORK/reddit.py"
(cd "$WORK" && "$VENV/bin/pyinstaller" --onefile --clean --strip \
    --name reddit reddit.py >/dev/null)

echo "==> verifying"
BIN="$WORK/dist/reddit"
"$BIN" --version
file "$BIN" | sed 's/^/    /'
ls -lh "$BIN" | awk '{print "    size: " $5}'

DEST="$HERE/dist"
mkdir -p "$DEST"
cp "$BIN" "$DEST/reddit"
echo "==> installed to $DEST/reddit"

if [ "${1:-}" = "--install" ]; then
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$BIN" "$HOME/.local/bin/reddit"
    echo "==> also installed to ~/.local/bin/reddit (ensure it is on PATH)"
fi
