set -euo pipefail
# Grant sudo once for Mac Cleaner (GUI password dialog).
# Exit 0 = active, 1 = failed, 2 = cancelled.
if sudo -n true 2>/dev/null; then
  echo already
  exit 0
fi
PW=$(osascript -e 'display dialog "Mac Cleaner needs admin access once for system cleanup and optimize.\n\nEnter your password; it stays active while this app is open so Mole will not ask again." default answer "" with title "Mac Cleaner" with icon caution with hidden answer' -e 'text returned of result' 2>/dev/null) || exit 2
if printf '%s\n' "$PW" | sudo -S -p "" -v >/dev/null 2>&1; then
  unset PW
  echo granted
  exit 0
fi
unset PW
exit 1
