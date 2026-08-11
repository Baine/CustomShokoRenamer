#!/bin/bash
# Place a read-only .nomedia marker in every library import folder's
# !ShokoRelayVFS subfolder, so media scanners ignore Shoko's VFS content.
# Covers Anime + Hentai x Movies + Shows x all categories under /mnt/user/array.
set -euo pipefail

base="/mnt/user/array"

for root in "$base/Anime" "$base/Hentai"; do
  [ -d "$root" ] || continue
  while IFS= read -r importfolder; do
    vfs="$importfolder/!ShokoRelayVFS"
    if [ ! -d "$vfs" ]; then
      mkdir -p "$vfs"
      chown nobody:users "$vfs"
    fi
    : > "$vfs/.nomedia"
    chmod 444 "$vfs/.nomedia"
    echo "marked $vfs"
  done < <(find "$root" -mindepth 2 -maxdepth 2 -type d \
    \( -name "GerDub" -o -name "GerSub" -o -name "Other" -o -name "_manual" \))
done
