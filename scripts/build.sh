#!/bin/bash
# Baixa o firmware do AR9271 (htc_9271.fw) do pacote firmware-atheros do Debian
# e monta a estrutura do modulo Magisk.
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
FW_DIR="$DIR/system/vendor/firmware"
DEB_URL="https://deb.debian.org/debian/pool/non-free-firmware/f/firmware-nonfree/firmware-atheros_20260622-1_all.deb"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$FW_DIR"
echo "Baixando firmware-atheros..."
curl -fsSL --max-time 120 -o "$TMP/fw.deb" "$DEB_URL"

echo "Extraindo htc_9271.fw..."
dpkg-deb -x "$TMP/fw.deb" "$TMP/x"
FW_SRC="$(find "$TMP/x" -name "htc_9271.fw" | head -1)"
[ -n "$FW_SRC" ] || { echo "ERRO: htc_9271.fw nao encontrado no pacote" >&2; exit 1; }
cp "$FW_SRC" "$FW_DIR/htc_9271.fw"

ls -l "$FW_DIR/htc_9271.fw"
echo "OK. Estrutura do modulo:"
find "$DIR" -type f | grep -v build.sh
