#!/usr/bin/env bash
# shot.sh <log> <png> <заголовок> [--from N --to M] — «скриншот терминала» из лога.
# В копии лога подсвечиваются команды ($), ошибки (красным) и успехи (зелёным); сам лог остаётся без ANSI.
# MODE=diff — для вывода diff -u: зелёные «+», красные «-», голубые «@@» (подсветка по словам отключена).
# Рендерер: ~/bin/render-term.py (Python + PIL).
set -euo pipefail
log=$1; png=$2; title=$3; shift 3
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
expand -t 8 "$log" | awk -v mode="${MODE:-log}" '
  /^\$ /                                    { print "\033[1;32m" $0 "\033[0m"; next }
  mode == "diff" && /^@@/                   { print "\033[36m" $0 "\033[0m"; next }
  mode == "diff" && /^\+/ && !/^\+\+\+/     { print "\033[32m" $0 "\033[0m"; next }
  mode == "diff" && /^-/  && !/^---/        { print "\033[31m" $0 "\033[0m"; next }
  mode == "diff"                            { print; next }
  /Error|NXDOMAIN|Could not resolve|ErrImagePull|ImagePullBackOff|not found|HTTP 000|schema 1|schemaVersion: 1|exit code|ошибок резолва = [1-9]/ { print "\033[31m" $0 "\033[0m"; next }
  /HTTP 200|Running|successfully rolled out|created|configured|unchanged|schemaVersion: 2|<title>Welcome|ошибок резолва = 0|canonical name/ { print "\033[32m" $0 "\033[0m"; next }
  { print }' > "$tmp"
python3 ~/bin/render-term.py "$tmp" "$png" --title "$title" --wrap 150 "$@"
