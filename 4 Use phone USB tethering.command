#!/bin/sh
# Phone USB tethering runs automatically in the background. This shows its status,
# or starts it by hand if the background service isn't installed.
if launchctl print system 2>/dev/null | grep -qi muta; then
  echo "Phone USB tethering runs automatically. Plug in the phone and turn on USB tethering."
  "$HOME/.cargo/bin/muta" status
else
  echo "Background service not installed - starting by hand. Keep this window open (Ctrl-C to stop)."
  sudo "$HOME/.cargo/bin/muta" run -v
fi
