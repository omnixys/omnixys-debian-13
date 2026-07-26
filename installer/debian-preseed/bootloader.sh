#!/usr/bin/env bash

debian_boot_params() {
  cat <<EOF
auto=true priority=critical file=/cdrom/preseed.cfg \
language=$LANGUAGE country=$COUNTRY locale=$LOCALE keymap=$KEYBOARD time/zone=$TIMEZONE
EOF
}
