#!/usr/bin/env bash
# shellcheck disable=SC2034 # renderer globals are consumed by sourced functions
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDERER="$ROOT_DIR/installer/debian-preseed/renderer.sh"
BUILDER="$ROOT_DIR/installer/debian-preseed/builder.sh"

die() { echo "die: $*" >&2; exit 1; }
# shellcheck disable=SC1090
source "$RENDERER"

grep -q 'omnixys-partman.sh' "$BUILDER"
if grep -q 'omnixys-disk-detect.sh' "$BUILDER"; then
  echo "legacy disk-detect helper is still packaged"
  exit 1
fi

SANDBOX="$(mktemp -d)"
cleanup() {
  status="$1"
  if [[ "${KEEP_TEST_SANDBOX:-false}" == "true" ]]; then
    echo "Preserved test sandbox: $SANDBOX" >&2
  else
    rm -rf "$SANDBOX"
  fi
  exit "$status"
}
trap 'cleanup "$?"' EXIT
BIN="$SANDBOX/bin"
mkdir -p "$BIN"

cat >"$BIN/list-devices" <<'EOF'
#!/bin/sh
[ "$1" = "disk" ]
printf '%b' "$DISK_LIST"
EOF
cat >"$BIN/debconf-set" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>"$DEBCONF_LOG"
[ "${DEBCONF_FAIL_KEY:-}" != "$1" ]
EOF
chmod +x "$BIN/list-devices" "$BIN/debconf-set"

render_partman() {
  GENERATED_DIR="$SANDBOX/generated-$1-$2"
  PARTITION_MODE="$1"
  TARGET_DISK_MODE="$2"
  TARGET_DISK="${3:-}"
  TARGET_DISK_BY_ID="${4:-}"
  IDENTITY_DEVICE_LABEL=OMNIXYS_ID
  FILESYSTEM=btrfs
  mkdir -p "$GENERATED_DIR"
  debian_render_partman_script
  PARTMAN_SCRIPT="$GENERATED_DIR/omnixys-partman.sh"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "$PARTMAN_SCRIPT"
  fi
}

reset_fixture() {
  FIXTURE="$SANDBOX/fixture-$1"
  DEV="$FIXTURE/dev"
  SYS="$FIXTURE/sys-block"
  MOUNTS="$FIXTURE/mounts"
  DEBCONF_LOG="$FIXTURE/debconf.log"
  WIPE_LOG="$FIXTURE/wipe.log"
  PARTMAN_LOG="$FIXTURE/partman.log"
  mkdir -p "$DEV/disk/by-label" "$DEV/disk/by-id" "$SYS" "$FIXTURE/transports"
  : >"$MOUNTS"
  : >"$DEBCONF_LOG"
  : >"$WIPE_LOG"
}

add_disk() {
  local name="$1"
  local removable="$2"
  local transport="${3:-pci}"
  mkdir -p "$SYS/$name" "$FIXTURE/transports/$transport/$name"
  : >"$DEV/$name"
  printf '%s\n' "$removable" >"$SYS/$name/removable"
  ln -s "$FIXTURE/transports/$transport/$name" "$SYS/$name/device"
}

add_partition() {
  : >"$DEV/$1"
}

run_partman() {
  env \
    PATH="$BIN:$PATH" \
    DISK_LIST="$DISK_LIST" \
    DEBCONF_LOG="$DEBCONF_LOG" \
    DEBCONF_FAIL_KEY="${DEBCONF_FAIL_KEY:-}" \
    OMNIXYS_DEV_ROOT="$DEV" \
    OMNIXYS_SYS_BLOCK_ROOT="$SYS" \
    OMNIXYS_PROC_MOUNTS="$MOUNTS" \
    OMNIXYS_EFI_ROOT="$FIXTURE/efi" \
    OMNIXYS_PARTMAN_TEST_MODE=true \
    OMNIXYS_WIPE_LOG="$WIPE_LOG" \
    OMNIXYS_PARTMAN_LOG="$PARTMAN_LOG" \
    OMNIXYS_FAIL_WIPE_DISK="${OMNIXYS_FAIL_WIPE_DISK:-}" \
    sh "$PARTMAN_SCRIPT"
}

# Multiple internal disks plus two kinds of USB, install media, identity media,
# and a mounted disk. Only the internal pool is wiped and NVMe wins selection.
reset_fixture multi
for disk in nvme1n1 nvme0n1 vdb sda xvda mmcblk0; do add_disk "$disk" 0 pci; done
add_disk sdc 1 usb1
add_disk sdd 0 usb2
add_disk sde 0 pci
add_disk sdf 0 pci
add_disk sdg 0 pci
add_partition sde1
add_partition sdf1
add_partition sdg1
ln -s ../../sdf1 "$DEV/disk/by-label/OMNIXYS_ID"
printf '/dev/sde1 /cdrom iso9660 ro 0 0\n/dev/sdg1 /mnt ext4 rw 0 0\n' >"$MOUNTS"
DISK_LIST='/dev/sdd\n/dev/nvme1n1\n/dev/sda\n/dev/sdc\n/dev/nvme0n1\n/dev/vdb\n/dev/sde\n/dev/sdf\n/dev/sdg\n/dev/xvda\n/dev/mmcblk0\n'
render_partman erase auto
run_partman
for disk in /dev/nvme1n1 /dev/nvme0n1 /dev/vdb /dev/sda /dev/xvda /dev/mmcblk0; do
  [[ "$(grep -Fxc "$disk" "$WIPE_LOG")" -eq 1 ]]
done
for disk in /dev/sdc /dev/sdd /dev/sde /dev/sdf /dev/sdg; do
  if grep -Fxq "$disk" "$WIPE_LOG"; then
    echo "protected disk was wiped: $disk"
    exit 1
  fi
done
[[ "$(wc -l <"$WIPE_LOG" | tr -d ' ')" -eq 6 ]]
grep -Fxq 'partman-auto/disk /dev/nvme0n1' "$DEBCONF_LOG"
grep -Fxq 'grub-installer/bootdev /dev/nvme0n1' "$DEBCONF_LOG"
grep -q 'method{ biosgrub }' "$DEBCONF_LOG"

# UEFI selection uses the EFI recipe.
reset_fixture uefi
add_disk nvme0n1 0 pci
mkdir -p "$FIXTURE/efi"
DISK_LIST='/dev/nvme0n1\n'
render_partman erase auto
run_partman
grep -q 'method{ efi }' "$DEBCONF_LOG"
grep -q 'mountpoint{ /boot/efi }' "$DEBCONF_LOG"

# SATA-only selection remains deterministic.
reset_fixture sata
add_disk sdb 0 pci
add_disk sda 0 pci
DISK_LIST='/dev/sdb\n/dev/sda\n'
render_partman erase auto
run_partman
grep -Fxq 'partman-auto/disk /dev/sda' "$DEBCONF_LOG"

# Empty safe pool fails closed without selecting or wiping a disk.
reset_fixture empty
add_disk sdc 1 usb1
add_disk sdd 0 usb2
DISK_LIST='/dev/sdc\n/dev/sdd\n'
render_partman erase auto
if run_partman; then
  echo "empty safe disk pool unexpectedly succeeded"
  exit 1
fi
[[ ! -s "$WIPE_LOG" ]]
if grep -q '^partman-auto/disk ' "$DEBCONF_LOG"; then
  echo "empty pool selected a target"
  exit 1
fi

# A wipe error fails before any target is written.
reset_fixture wipe_failure
add_disk nvme0n1 0 pci
add_disk sda 0 pci
DISK_LIST='/dev/nvme0n1\n/dev/sda\n'
OMNIXYS_FAIL_WIPE_DISK=/dev/sda
render_partman erase auto
if run_partman; then
  echo "simulated wipe failure unexpectedly succeeded"
  exit 1
fi
unset OMNIXYS_FAIL_WIPE_DISK
if grep -q '^partman-auto/disk ' "$DEBCONF_LOG"; then
  echo "wipe failure still selected a target"
  exit 1
fi

# LVM auto selects one disk but never performs the erase-mode mass wipe.
reset_fixture lvm
add_disk vdb 0 pci
add_disk vda 0 pci
DISK_LIST='/dev/vdb\n/dev/vda\n'
render_partman lvm auto
run_partman
[[ ! -s "$WIPE_LOG" ]]
grep -Fxq 'partman-auto/disk /dev/vda' "$DEBCONF_LOG"
if grep -q '^partman-auto/expert_recipe ' "$DEBCONF_LOG"; then
  echo "LVM unexpectedly received an expert recipe"
  exit 1
fi

# Manual and by-id modes set only the explicit target and do not mass-wipe.
reset_fixture explicit
add_disk vda 0 pci
add_disk vdb 0 pci
DISK_LIST='/dev/vda\n/dev/vdb\n'
render_partman erase manual /dev/vdb
run_partman
[[ ! -s "$WIPE_LOG" ]]
grep -Fxq 'partman-auto/disk /dev/vdb' "$DEBCONF_LOG"

: >"$DEBCONF_LOG"
ln -s ../../vda "$DEV/disk/by-id/omnixys-system"
render_partman erase by-id '' /dev/disk/by-id/omnixys-system
run_partman
[[ ! -s "$WIPE_LOG" ]]
grep -Fxq 'partman-auto/disk /dev/vda' "$DEBCONF_LOG"

# Explicit modes cannot opt into wiping or partitioning protected USB media.
reset_fixture explicit_usb
add_disk sda 0 usb1
DISK_LIST='/dev/sda\n'
render_partman erase manual /dev/sda
if run_partman; then
  echo "explicit USB target unexpectedly succeeded"
  exit 1
fi
[[ ! -s "$WIPE_LOG" ]]
if grep -q '^partman-auto/disk ' "$DEBCONF_LOG"; then
  echo "explicit USB target reached partman"
  exit 1
fi

# Debconf failures are fatal.
reset_fixture debconf_failure
add_disk vda 0 pci
DISK_LIST='/dev/vda\n'
DEBCONF_FAIL_KEY=partman-auto/disk
render_partman lvm auto
if run_partman; then
  echo "debconf failure unexpectedly succeeded"
  exit 1
fi
unset DEBCONF_FAIL_KEY

echo "Partman disk safety tests passed"
