#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

find ./schemas -type f -name '*.json' -print0 | while IFS= read -r -d '' file; do
    tmp="$(mktemp)"
    jq . "$file" > "$tmp"
    mv "$tmp" "$file"
    echo "formatted $file"
done
