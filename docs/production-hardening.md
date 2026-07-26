# Production Hardening Guide

Use this guide before applying the installer to real hardware.

## Recommended production baseline

In configs/production.env:

- INSTALLER=debian-preseed
- ARCH=amd64
- DEBIAN_MAJOR=13
- DEBIAN_RELEASE=stable
- DEBIAN_ISO_SHA256=<set this to the official checksum>
- PARTITION_MODE=lvm
- FILESYSTEM=ext4
- INSTALL_OPENSSH=true
- INSTALL_STANDARD_UTILITIES=true
- SSH_PASSWORD_AUTH=false
- SSH_PERMIT_ROOT_LOGIN=no
- SSH_PUBLIC_KEY=<required, non-empty>

## Security notes

1. Always set SSH_PUBLIC_KEY to a real key before production use.
2. Keep SSH_PASSWORD_AUTH=false for key-only SSH access.
3. Keep root login disabled (SSH_PERMIT_ROOT_LOGIN=no).
4. Use official Debian checksum pinning via DEBIAN_ISO_SHA256.
5. Never run with ERASE_DISK=true on unknown target disks.

## Pre-flight checklist

1. Run dry-run:
   ./build.sh --config configs/production.env --dry-run
2. Ensure readiness ends with `Ready to build`.
3. Build ISO and verify sha256 output.
4. Validate BIOS and UEFI boot in VM before hardware deployment.

## Post-install validation

1. SSH key login works.
2. Password login is disabled.
3. Root SSH login is disabled.
4. Hostname, timezone, locale, and partitioning match profile.
