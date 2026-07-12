#!/bin/sh
# Silent probe: exit 0 if sudo timestamp is already valid.
sudo -n true 2>/dev/null
