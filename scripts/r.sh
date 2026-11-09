#!/usr/bin/env bash
# r "команда" — печатает "$ команда" и выполняет её (для логов ДЗ). Вывод ошибок тоже в лог.
for c in "$@"; do
  printf '$ %s\n' "$c"
  bash -c "$c" 2>&1 < /dev/null | grep -v -E '^Warning: version difference between client'
  echo
done
