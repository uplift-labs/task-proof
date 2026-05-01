#!/bin/bash
# json-field.sh — Shared JSON field extraction for task-proof guards
# Tolerates both compact {"key":"val"} and pretty-printed {"key": "val"} JSON.
#
# Usage: . "$(dirname "$0")/../lib/json-field.sh"
#        val=$(json_field "file_path" "$INPUT")

json_field() {
  _key="$1"
  _json="$2"
  printf '%s' "$_json" | grep -oE "\"${_key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//'
}

# json_field_long — extract a JSON string value that may contain escaped quotes/newlines.
# Uses awk to handle \" and \\\\ inside the value. Returns unescaped content.
json_field_long() {
  _key="$1"
  _json="$2"
  printf '%s' "$_json" | awk -v key="$_key" '
    BEGIN { RS="\0" }
    {
      pat = "\"" key "\"[[:space:]]*:[[:space:]]*\""
      idx = match($0, pat)
      if (idx == 0) exit
      rest = substr($0, idx + RLENGTH)
      out = ""
      i = 1
      while (i <= length(rest)) {
        c = substr(rest, i, 1)
        if (c == "\\") {
          nc = substr(rest, i+1, 1)
          if (nc == "\"") { out = out "\""; i += 2; continue }
          if (nc == "n") { out = out "\n"; i += 2; continue }
          if (nc == "t") { out = out "\t"; i += 2; continue }
          if (nc == "\\") { out = out "\\"; i += 2; continue }
          out = out c; i++; continue
        }
        if (c == "\"") break
        out = out c
        i++
      }
      printf "%s", out
    }
  '
}
