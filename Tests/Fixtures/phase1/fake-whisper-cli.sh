#!/bin/sh
set -eu
output=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-of" ]; then
    shift
    output="$1"
  fi
  shift
done
[ -n "$output" ]
printf '{"result":{"language":"en"},"transcription":[]}' > "${output}.json"
printf 'speaker: Ana\nminutes: 12\napproved: true\n'
