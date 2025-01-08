#!/bin/sh
# TODO: make this a custom script, `ip` is not available on macos
ip -json route get 8.8.8.8 | jq -r '.[].prefsrc'
