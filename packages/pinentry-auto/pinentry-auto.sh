#!/usr/bin/env bash
# Assuan-aware pinentry multiplexer. Picks pinentry-curses if the gpg client
# advertised a tty (`OPTION ttyname=…` non-empty); otherwise pinentry-gnome3.
set -euo pipefail

printf 'OK Pleased to meet you\n'

backend=pinentry-gnome3
buffered=()

while IFS= read -r line; do
  case "$line" in
  "OPTION ttyname="?*) backend=pinentry-curses ;&
  "OPTION "* | RESET)
    printf 'OK\n'
    buffered+=("$line")
    ;;
  BYE)
    printf 'OK closing connection\n'
    exit 0
    ;;
  *) break ;;
  esac
done

# Replay the buffered handshake (and the line that broke us out) into the
# chosen backend, then become a transparent pump. The skip-loop drops the
# backend's greeting + one OK echo per replayed OPTION; it uses bash's
# byte-at-a-time `read` so there's no libc buffering or over-read.
n_skip=$((${#buffered[@]} + 1))

{
  printf '%s\n' "${buffered[@]}" "$line"
  exec cat
} |
  "$backend" |
  {
    for ((i = 0; i < n_skip; i++)); do read -r _ || break; done
    exec cat
  }
