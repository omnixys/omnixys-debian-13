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
decision aborts instead of falling back to a guessed device. Manual/by-id erase
and LVM remain on Debian's `atomic` recipe and do not perform the multi-disk wipe.

The hook logs detected disks, exact exclusion reasons, internal/wipe candidates,
wipe and partition-table-reread results, recipe selection, and both final Debconf
targets to `/var/log/installer/omnixys-partman.log`. Existing unmounted
partitions remain eligible, while a disk with any mounted partition stays
protected. A successful reread must also remove stale partition entries from
sysfs before partman continues.

For UTM/QEMU, the VM profile uses erase/manual with the known VirtIO target
`/dev/vda`. It follows the working v1.2.1 path through regular partman and its
built-in `atomic` recipe, without the low-level multi-disk wipe intended for
bare-metal auto mode. The partman message `No matching physical volumes found`
may be emitted during normal LVM udeb initialization and is not itself a failure.

Implemented API:

- validate
- render
- build
- verify
- package
