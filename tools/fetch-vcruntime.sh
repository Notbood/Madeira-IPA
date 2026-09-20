#!/usr/bin/env bash
set -euo pipefail

DEST="${GITHUB_WORKSPACE:-$PWD}/app/Madeira/x86_64-vcruntime"
INV="${GITHUB_WORKSPACE:-$PWD}/vcruntime-inventory.txt"
WORK="${RUNNER_TEMP:-/tmp}/vcredist"
NEEDED="concrt140 msvcp140 msvcp140_1 msvcp140_2 msvcp140_atomic_wait msvcp140_codecvt_ids vcamp140 vccorlib140 vcomp140 vcruntime140 vcruntime140_1"
CORE="concrt140 msvcp140 vcruntime140 vcruntime140_1"

command -v cabextract >/dev/null || brew install cabextract

rm -rf "$WORK"
mkdir -p "$WORK/L0" "$WORK/L1" "$WORK/L2" "$DEST"
cd "$WORK"

curl -fL https://aka.ms/vs/17/release/vc_redist.x64.exe -o vc_redist.x64.exe
shasum -a 256 vc_redist.x64.exe

cabextract -q -L -d L0 vc_redist.x64.exe || true
[ -n "$(ls -A L0)" ] || { echo "ERROR: nothing extracted from installer"; exit 1; }

pass() {
  find "$1" -type f ! -iname '*.dll' | while IFS= read -r f; do
    d="$2/${f#$1/}.d"
    mkdir -p "$d"
    cabextract -q -L -d "$d" "$f" >/dev/null 2>&1 || rmdir "$d" 2>/dev/null || true
  done
}
pass L0 L1
pass L1 L2

find L0 L1 L2 -type f | sort > "$INV"
echo "=== extracted files (first 120) ==="
head -120 "$INV"

missing_core=""
for name in $NEEDED; do
  best=""; best_size=0
  while IFS= read -r f; do
    file "$f" | grep -q 'x86-64' || continue
    size="$(wc -c < "$f" | tr -d ' ')"
    if [ "$size" -gt "$best_size" ]; then best="$f"; best_size="$size"; fi
  done < <(find L0 L1 L2 -type f -iname "${name}.dll*" 2>/dev/null)

  if [ -n "$best" ]; then
    cp "$best" "$DEST/${name}.dll"
    echo "OK  ${name}.dll <- $best"
  else
    echo "MISSING ${name}.dll"
    case " $CORE " in *" $name "*) missing_core="$missing_core $name" ;; esac
  fi
done

ls -l "$DEST"
[ -z "$missing_core" ] || { echo "ERROR: missing required:$missing_core"; exit 1; }
