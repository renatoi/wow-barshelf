#!/bin/bash
# Downloads the latest ArtTextureID.lua from Townlong Yak and generates
# TextureNames.lua with only Icon entries (for the icon picker search).
set -euo pipefail

SOURCE_URL="https://www.townlong-yak.com/framexml/live/Helix/ArtTextureID.lua/get"
OUTPUT="TextureNames.lua"

echo "Downloading ArtTextureID.lua from Townlong Yak..."
RAW=$(curl -sfL "$SOURCE_URL")
if [ -z "$RAW" ]; then
  echo "ERROR: Failed to download source file" >&2
  exit 1
fi

echo "Filtering to Icon entries and generating $OUTPUT..."
cat > "$OUTPUT" <<'HEADER'
-- Icon FileDataID → name mapping for the icon picker search.
-- Auto-generated from https://www.townlong-yak.com/framexml/live/Helix/ArtTextureID.lua
-- Only Interface/Icons entries are included. Run scripts/update-texture-names.sh to refresh.
Barshelf_TextureNames = {
HEADER

echo "$RAW" | grep -i '"Interface/Icons/' | \
  sed 's/.*\[\([0-9]*\)\]="Interface\/Icons\/\(.*\)".*/[\1]="\2",/' | \
  sort -t'[' -k2 -n >> "$OUTPUT"

echo "}" >> "$OUTPUT"

LINES=$(wc -l < "$OUTPUT")
echo "Done: $OUTPUT ($LINES lines)"
