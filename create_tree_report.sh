#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
start_dir="$(cd "$script_dir/.." && pwd)"
report_dir="$script_dir/Tree_report"
mkdir -p "$report_dir"
output_file="$report_dir/tree_$(date +%F).txt"

dirs_count=$(find "$start_dir" -mindepth 1 -type d | wc -l)
files_count=$(find "$start_dir" -mindepth 1 -type f | wc -l)

{
  echo "${dirs_count} directories, ${files_count} files"

  if command -v tree >/dev/null 2>&1; then
    tree -a --noreport "$start_dir"
  else
    find "$start_dir" -mindepth 1 | sort | awk -v base="$start_dir" -F'/' '
      {
        if ($NF == "") next
        rel = $0
        sub("^" base "/?", "", rel)
        n = split(rel, parts, "/")
        depth = n - 1
        indent = ""
        for (i = 0; i < depth; i++) indent = indent "    "
        print indent "|-- " parts[n]
      }
    '
  fi
} > "$output_file"

echo "Created: $output_file"
