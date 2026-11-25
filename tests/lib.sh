#!/bin/bash
# Minimal test helpers (no external dependency): assert_* and summary.
T_PASS=0
T_FAIL=0
T_NAME=""

function t_start { T_NAME=$1; }
function t_ok { T_PASS=$((T_PASS + 1)); printf '  ok   %s\n' "$T_NAME${1:+ - $1}"; }
function t_ko {
  T_FAIL=$((T_FAIL + 1))
  printf '  FAIL %s - %s\n' "$T_NAME" "$1"
  [ $# -gt 1 ] && printf '       %s\n' "${@:2}"
  return 0
}

function assert_eq { # expected actual [message]
  if [ "$1" = "$2" ]; then t_ok "${3:-}"; else t_ko "${3:-values differ}" "expected: [$1]" "actual:   [$2]"; fi
}
function assert_contains { # haystack needle [message]
  if [[ "$1" == *"$2"* ]]; then t_ok "${3:-}"; else t_ko "${3:-missing text}" "expected to contain: [$2]" "in: [$1]"; fi
}
function assert_not_contains { # haystack needle [message]
  if [[ "$1" != *"$2"* ]]; then t_ok "${3:-}"; else t_ko "${3:-unexpected text}" "must not contain: [$2]"; fi
}
function assert_file_contains { # file needle [message]
  if grep -qF -- "$2" "$1" 2>/dev/null; then t_ok "${3:-}"; else t_ko "${3:-file $1 misses text}" "expected: [$2]"; fi
}
function assert_file_not_contains { # file needle [message]
  if ! grep -qF -- "$2" "$1" 2>/dev/null; then t_ok "${3:-}"; else t_ko "${3:-file $1 has unexpected text}" "must not contain: [$2]"; fi
}
function assert_rc { # expected-rc actual-rc [message]
  assert_eq "$1" "$2" "${3:-exit code}"
}

function t_summary {
  printf '\n%s passed, %s failed\n' "$T_PASS" "$T_FAIL"
  [ "$T_FAIL" -eq 0 ]
}
