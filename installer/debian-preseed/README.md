# debian-preseed backend

Production backend for Debian 13 unattended installation using preseed.

The renderer generates an early identity script using the native cdebconf
frontend and a separate late network script. Static network values are written
directly into the target filesystem and validated before installation finishes;
four empty network values preserve DHCP.

Partitioning uses a separate `omnixys-partman.sh` hook at
`partman/early_command`. Auto erase mode rejects USB/removable, mounted,
installation, and identity media, clears every remaining internal disk, and
selects one deterministic system disk. BIOS and UEFI receive separate GPT expert
recipes with the configured root filesystem. Any unsafe or incomplete disk
decision aborts instead of falling back to a guessed device. LVM remains on the
Debian `atomic` recipe and does not perform the multi-disk wipe.

The hook logs detected disks, exact exclusion reasons, internal/wipe candidates,
wipe and partition-table-reread results, recipe selection, and both final Debconf
targets to `/var/log/installer/omnixys-partman.log`. Existing unmounted
partitions remain eligible, while a disk with any mounted partition stays
protected. A successful reread must also remove stale partition entries from
sysfs before partman continues.

For UTM/QEMU, the VM profile uses erase/auto. VirtIO `/dev/vda` participates in
the normal `nvme`, `vd`, `sd`, `xvd`, `mmcblk` priority order. The partman message
`No matching physical volumes found` may be emitted during normal LVM udeb
initialization and must not be treated as the disk-classification result.

Implemented API:

- validate
- render
- build
- verify
- package
