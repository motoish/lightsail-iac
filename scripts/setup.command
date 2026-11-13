#!/bin/bash
# Double-click in Finder to provision tokyo-dev and copy the SFM profile.
# Run `terraform apply` first when the instance is new or was destroyed.
#
# First open: right-click → Open, if macOS blocks an unidentified developer.

set -u
cd "$(cd "$(dirname "$0")/.." && pwd)" || exit 1

./scripts/setup.sh "$@"
status=$?

echo
if ((status == 0)); then
  printf 'SFM profile is on the clipboard. Paste it into the tokyo-dev Profile, then start SFM.\n'
else
  printf 'Setup failed (exit %s). See the messages above.\n' "$status"
fi

read -r -p 'Press Enter to close...'
exit "$status"
