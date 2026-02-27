#!/usr/bin/env bash
set -euo pipefail

output_file="tree_$(date +%F).txt"

dirs_count=$(find . -mindepth 1 -type d | wc -l)
files_count=$(find . -mindepth 1 -type f | wc -l)

{
  echo "${dirs_count} directories, ${files_count} files"

  if command -v tree >/dev/null 2>&1; then
    tree -a --noreport
  else
    find . -mindepth 1 | sort | awk -F'/' '
      {
        if ($NF == "") next
        depth = NF - 2
        indent = ""
        for (i = 0; i < depth; i++) indent = indent "    "
        print indent "|-- " $NF
      }
    '
  fi
} > "$output_file"

echo "Created: $output_file"
