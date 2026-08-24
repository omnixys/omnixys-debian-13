# Omnixys Installer Framework

Omnixys Installer Framework is a modular installer framework with an installer-agnostic core.

Version 1.0 focus:

- Fully implement Debian 13 unattended installation backend using Preseed.
- Keep core generic so additional backends can be added later without core rewrites.

## Current Structure

```text
omnixys-debian-13/
├── build.sh
├── config.example.env
├── configs/
├── core/
├── installer/
│   ├── debian-preseed/
│   ├── ubuntu-autoinstall/
│   └── fedora-kickstart/
├── modules/
├── hooks/
├── templates/
├── plugins/
├── logs/
├── downloads/
├── output/
├── tests/
├── docs/
└── .github/workflows/
```

## Design Principles

- Modularity
- Reusability
- Reproducibility
- Extensibility

Core rules:

- Core must not contain backend-specific logic.
- Installer backend is selected through config.
- New features should be integrated through backend APIs, modules, hooks, or plugins.

## Backend API

Each backend implements:

- `validate()`
- `render()`
- `build()`
- `verify()`
- `package()`

See `docs/backend-api.md`.

## Quick Start

```bash
git clone https://...
cd omnixys-debian-13

cp config.example.env config.env
nano config.env

./build.sh
```

Build output:

- `output/omnixys-debian-13-amd64-auto.iso`
- `output/omnixys-debian-13-amd64-auto.iso.sha256`
- `output/omnixys-debian-13-arm64-auto.iso`
- `output/omnixys-debian-13-arm64-auto.iso.sha256`
- `logs/build.log`
- `logs/install.log`

## CLI

```bash
./build.sh --help
./build.sh --version
./build.sh --dry-run
./build.sh --config configs/homelab.env
./build.sh --config configs/production.env --arches amd64,arm64
```

## Key Configuration

Framework level:

- `CONFIG_SCHEMA_VERSION=1`
- `INSTALLER=debian-preseed`
- `ARCH=amd64`
- `ARCHES=amd64,arm64` (optional multi-arch build list)
- `INSTALLER_VERSION=1.0.0`

`INSTALLER_VERSION` also determines the ISO Volume ID and the boot-menu title.
For example, `1.2.1`, `1.2.1-beta.1`, and `1.2.1+build.5` produce Volume ID
`OMNIXYS121`; the visible title is `Omnixys Debian Installer 1.2.1` (including
metadata when present).

Debian backend:

- `DEBIAN_MAJOR=13`
- `DEBIAN_RELEASE=stable`
- `DEBIAN_ISO_URL=` (optional override)
- `DEBIAN_ISO_SHA256=` (recommended)

Install behavior:

- `IDENTITY_SOURCE=none|usb-env`
- `IDENTITY_REQUIRED=true|false`
- `IDENTITY_FILE_PATH=/identity.env`
- `IDENTITY_DEVICE_LABEL=OMNIXYS_ID`
- `IDENTITY_EMBED=true|false` (build-time only; see Runtime Identity Override)
- `TARGET_DISK_MODE=auto|by-id|manual`
- `TARGET_DISK_BY_ID=/dev/disk/by-id/...` (required for `by-id`)
- `TARGET_DISK=/dev/...` (required for `manual`)
- `PARTITION_MODE=erase|lvm|custom`
- `FILESYSTEM=ext4|xfs|btrfs`
- `INSTALL_OPENSSH=true|false`
- `INSTALL_STANDARD_UTILITIES=true|false`
- `INSTALL_FIRMWARE=true|false`
- `SSH_PASSWORD_AUTH=true|false`
- `SSH_PERMIT_ROOT_LOGIN=no|prohibit-password|yes`

### Automatic disk selection and erase mode

Disk discovery runs from Debian Installer's `partman/early_command`, immediately
before partitioning. This avoids retaining a guessed `/dev/sda` value when NVMe or
virtio devices appear later in installer startup.

With `PARTITION_MODE=erase` and `TARGET_DISK_MODE=auto`, every safely classified
internal HDD, SSD, NVMe, or virtio disk has its partition tables and detectable
signatures removed. One disk is then selected for EFI/BIOS boot and `/`, using the
stable priority `nvme`, `vd`, `sd`, `xvd`, `mmcblk` and alphabetical order within
each class. Other internal disks remain empty and unpartitioned.

USB devices (including USB storage reporting `removable=0`), removable devices,
mounted disks, the installation medium, and the device labeled by
`IDENTITY_DEVICE_LABEL` are always excluded. There is no fallback to an excluded
device. Missing safe disks, wipe failures, and target-selection failures stop the
automatic installation. Manual and by-id modes never perform the low-level
multi-disk wipe. In regular erase mode they use Debian's built-in `atomic`
recipe; LVM also remains on `atomic` and is outside the multi-disk erase behavior.

`/var/log/installer/omnixys-partman.log` records the complete decision: detected
devices, exclusions with reasons, internal and wipe candidates, wipe and
partition-table-reread results, selected recipe/system disk, and the final
`partman-auto/disk` and `grub-installer/bootdev` values. Existing unmounted
partitions do not exclude a disk; any genuinely mounted partition keeps its parent
disk protected. After a wipe, stale kernel partition entries are a fatal error.

## Profiles

Included profile examples:

- `configs/homelab.env`
- `configs/production.env`
- `configs/lab.env`
- `configs/vm.env`

Production deployment guidance:

- `docs/production-hardening.md`

## VM Installs (UTM / ARM64)

For UTM/ARM64 VM installations always use `configs/vm.env`:

```bash
./build.sh --config configs/vm.env --arches arm64
```

`configs/vm.env` intentionally sets `INSTALL_FIRMWARE=false` because the UTM VM
uses VirtIO/vmnet virtual devices and does not require additional proprietary
firmware packages (`firmware-linux`, `firmware-misc-nonfree`).

The VM profile uses `PARTITION_MODE=erase`, `TARGET_DISK_MODE=manual`, and the
known VirtIO target `/dev/vda`. This deliberately matches the working v1.2.1 VM
path: Debian's regular partitioner and built-in `atomic` recipe recreate the
filesystem without running the bare-metal multi-disk discovery and low-level
wipe. Newly created UTM disks do not need that additional erase pass.

The partman message `No matching physical volumes found` can occur while its LVM
and device-mapper components initialize and is not by itself evidence that the
VirtIO disk is missing. Use `omnixys-partman.log` to identify the actual disk,
wipe, reread, target, or recipe failure.

The regular `config.env` is intended for bare-metal systems such as the
OptiPlex and can contain different settings, in particular
`INSTALL_FIRMWARE=true`, where proprietary firmware is needed for real
hardware (GPU, Wi-Fi, NICs, ...).

### GitHub Release Assets

GitHub release ISOs named `omnixys-debian-13-<arch>-<version>.iso` are
production/bare-metal images built from `configs/production.env`
(`INSTALL_FIRMWARE=true`, `IDENTITY_REQUIRED=true`) and are **not** suitable
for UTM/ARM64 VM installations.

Since the release pipeline also publishes dedicated VM images:
`omnixys-debian-13-<arch>-<version>-vm.iso`. These are built exclusively from
`configs/vm.env` (no production secrets, no identity-USB requirement,
`INSTALL_FIRMWARE=false`) and are identifiable by the `-vm` filename suffix.
Use the `-vm` image for UTM/ARM64 VM installs, or build manually:

```bash
./build.sh --config configs/vm.env --arches amd64,arm64
```

`-vm` images (and local VM builds from `configs/vm.env`) use the same `usb-env`
identity provisioning as the production images, but with `IDENTITY_REQUIRED=false`:
identity values are applied when present, otherwise the VM build-time defaults are
used. To provision a VM dynamically, attach a volume/USB with the `OMNIXYS_ID`
label containing `identity.env`, or bake `./identity.env` into the ISO at build time
(see "Runtime Identity Override"). With `IDENTITY_CONFIRM=true`, the active Debian
Installer frontend always presents the resulting identity and network values for
confirmation. Leaving all four network fields empty keeps DHCP enabled.

## Secure Boot Status

- BIOS: remaster path implemented and patched via boot config update
- UEFI: remaster path implemented and patched via boot config update
- Secure Boot: intended to preserve original signed EFI chain via xorriso replay; requires environment test validation

Important note:

- The current implementation injects generated preseed and metadata into the output ISO and patches common GRUB/ISOLINUX paths.
- Final acceptance still requires BIOS/UEFI/Secure-Boot execution tests in CI/VM.

## Dry-Run Readiness Report

`./build.sh --dry-run` emits a readiness checklist, including:

- Config valid
- Preseed generated
- ISO source resolved
- ISO/source verification passed
- Builder passed
- Ready to build

Additionally, config schema warnings are printed when expected keys are missing or unknown keys are present.

## Modules and Hooks

Modules are feature extensions in `modules/`.

Hooks are global lifecycle injection points:

- `hooks/pre-build`
- `hooks/post-build`
- `hooks/pre-install`
- `hooks/post-install`

## Plugins

Place trusted local plugins in `plugins/`.

Examples:

- `plugins/my-company-installer/`
- `plugins/my-lab-installer/`

## CI and Release

Included workflows:

- `ci.yml`: ShellCheck + dry-run + per-push/per-PR ISO artifacts; commitlint validates Conventional Commit messages
- `boot-tests.yml`: manual build + BIOS/UEFI smoke tests (matrix-ready backend structure)
- `semantic-release.yml`: automatic SemVer releases only after the complete `CI` workflow succeeds for a `main` push (tag + GitHub Release + changelog)
- `release.yml`: builds and uploads production and `-vm` assets (`.iso`, `.iso.sha256`) only after a successful Semantic Release run created a new release tag; manual reruns require an existing tag

Release builds require these GitHub Actions secrets:

- `USERNAME`
- `PASSWORD`
- `FULLNAME`
- `HOSTNAME`
- `SSH_PUBLIC_KEY`
- `DOMAIN` (optional)
- `OMNIXYS_TOKEN` (PAT with `contents: write`; required so the automatic release can trigger the asset build)

These values are injected into the temporary CI config at runtime and override the corresponding profile values for release builds.

## Download Channels

- Stable Releases: GitHub Releases assets (production and `-vm` images)
- CI Artifacts: per push and pull request workflow artifacts

## Conventional Commits and SemVer

Every successful CI run for a push to `main` is evaluated by semantic-release. Failed,
cancelled, or skipped CI runs cannot execute semantic-release or start release asset builds:

1. `ci.yml` must complete successfully.
2. `semantic-release.yml` determines the next version from Conventional Commits and creates the tag + GitHub Release.
3. `release.yml` starts after Semantic Release succeeds and only builds assets when the current `main` commit carries the newly created `v*` tag.

- `fix:` -> patch bump
- `feat:` -> minor bump
- `BREAKING CHANGE:` or `!` -> major bump
- No `fix:`/`feat:` commits -> no new release

Example commit types:

- `fix(installer): handle checksum edge case`
- `feat(workflow): add release asset pipeline`
- `feat!: change backend API`

The release commit is created with `[skip ci]` and does not trigger the pipeline again. Commit messages are enforced by commitlint.

## Safety Warning

When disk installation is fully active, settings like `ERASE_DISK=true` will destroy data on target disks.
Always test in VM first.

## Disk Selection Modes

The Debian backend supports three disk selection modes:

- `auto` (recommended default): installer runtime detects candidate disks, excludes the install medium, and continues only if exactly one non-removable disk is found.
- `by-id`: uses a stable path under `/dev/disk/by-id/...` and resolves it during installer startup.
- `manual`: uses a fixed `/dev/...` path from config.

Safety behavior:

- In `auto`, the installer never guesses when multiple candidates exist.
- If `auto` finds zero or more than one candidate disk, installation stops before partitioning.
- Existing configs without `TARGET_DISK_MODE` remain compatible and behave like `manual`.

## Runtime Identity Override (MVP)

The Debian backend can optionally override identity values at install time from an external `identity.env` file. The mechanism is identical for bare-metal (`configs/production.env`) and VM (`configs/vm.env`) images; only the required/optional policy differs.

- `IDENTITY_SOURCE=usb-env` enables lookup of `/identity.env` on `/cdrom` or on a removable medium labeled by `IDENTITY_DEVICE_LABEL` (for example `OMNIXYS_ID`).
- `IDENTITY_REQUIRED=true` aborts installation early (non-zero exit) when the identity file is missing or unreadable. Used by the production profile.
- `IDENTITY_REQUIRED=false` does **not** disable identity: the identity file is still consumed and overrides are applied when present. Only when it is missing does the installer continue with the build-time defaults. Used by the VM profile.
- `IDENTITY_CONFIRM=true` shows the resolved values on the installer console. Without input they are accepted automatically after five seconds. Enter `E` within that window to edit them with the native Debian Installer frontend. Values from `identity.env` take precedence; otherwise the build-time defaults are prefilled.
- Supported variables in `identity.env` are:
- `OMNIXYS_HOSTNAME`
- `OMNIXYS_DOMAIN` (optional)
- `OMNIXYS_FULLNAME`
- `OMNIXYS_USERNAME`
- `OMNIXYS_SSH_PUBLIC_KEY` (optional)
- `OMNIXYS_PASSWORD_HASH`
- `OMNIXYS_NETWORK_INTERFACE`
- `OMNIXYS_STATIC_IP`
- `OMNIXYS_STATIC_ROUTERS`
- `OMNIXYS_STATIC_DNS`

### Build-time identity embedding (`IDENTITY_EMBED`)

Embedding a runtime `identity.env` into the ISO is controlled independently of the
runtime lookup mechanism above, by the build-time switch `IDENTITY_EMBED`:

- `IDENTITY_EMBED=true` (default): if a local `./identity.env` is present at build
  time, it is baked into the ISO as `/identity.env` and picked up automatically at
  install time. This enables self-provisioning images (used by production/local
  builds).
- `IDENTITY_EMBED=false`: the ISO is always built **without** a baked identity, even
  if `./identity.env` is present. Runtime provisioning still works by attaching a
  medium labeled `OMNIXYS_ID`. Published `-vm` release images are built with this
  switch forced to `false`.

The build enforces the guarantee: when `IDENTITY_EMBED=false`, packaging fails if
`/identity.env` is nonetheless present in the final ISO. Published GitHub Release VM
assets additionally run an independent post-build check confirming no `/identity.env`
is shipped in the `-vm.iso`.

> Embedding a baked identity is a **build-time** policy. Disabling it does **not**
> turn off runtime identity provisioning from an attached `OMNIXYS_ID` medium.

Network mode is inferred from the four network values. When all are empty, the
installed system remains on DHCP. When all are set, the late installer phase writes
the selected interface, IPv4/CIDR, router and DNS values into
`/etc/dhcpcd.conf`. Partial or unresolved static configurations abort installation
instead of leaving a broken target configuration.

To supply identity to a VM install, either attach a volume/USB labeled with
`IDENTITY_DEVICE_LABEL` (for example `OMNIXYS_ID`) containing `identity.env`, or
place `./identity.env` in the repository root before building so it is baked into
the ISO as `/identity.env`.

Example:

```dotenv
OMNIXYS_HOSTNAME=omnixys-node-01
OMNIXYS_FULLNAME=Node Admin
OMNIXYS_USERNAME=ops
OMNIXYS_SSH_PUBLIC_KEY=ssh-ed25519 AAAA... user@host
OMNIXYS_PASSWORD_HASH=$6$rounds=656000$example$examplehash
```

You can generate a ready-to-use file with:

```bash
bash scripts/generate-identity-env.sh \
	--hostname omnixys-node-01 \
	--fullname "Node Admin" \
	--username ops \
	--ssh-public-key "ssh-ed25519 AAAA... user@host" \
	--generate-password \
	--output identity.env
```

The script prints the generated cleartext password once and writes only the hash into `identity.env`.
The domain is optional; omit `--domain` or leave `DOMAIN` empty when you do not want to set one.

This is the first runtime identity slice for Debian. The broader backend-agnostic Provisioning API and structured identity format remain the next architecture step.

## USB Write Mode (Important)

For physical installs, write the generated ISO in raw/block mode (for example Rufus DD mode or balenaEtcher).
Using extraction-style ISO modes can break `cdrom-detect` and produce "not a Debian CD" errors.

## Troubleshooting

### Installer logs

The `early_command` writes a step-by-step trace to `/var/log/installer/omnixys-early.log`
(inside the installer environment; also copied to the installed system under
`/var/log/installer/`). Every phase logs via `STEP`/`INFO`/`WARN`/`ERROR` lines, and fatal
problems end with an explicit `ABORT:` line. When an install fails, fetch this file first —
it names the exact phase and reason.

### Symptoms of a wiped install medium during installation

If `/cdrom` is empty, `/dists/trixie/Release` is reported missing, or the install device
(e.g. `/dev/sda`) disappears mid-install, the boot medium itself was overwritten while the
installer was running. Current builds are hardened against this (partition-freie device
Globs, Identity-Mount-Antikollision, `auto` disk mode excludes the install medium), so
rebuild the ISO with the current builder instead of debugging the old image.

### Builder gates

The builder refuses to ship a broken remaster and fails loudly before writing:

- `Work tree completeness verified` / gate failure naming missing paths: every path of the
  source ISO must still exist in the work tree after patching. A missing-path error means
  build-time patching deleted something; fix the patching logic, never bypass the gate.
- `Remaster structure verified`: post-build check for suite metadata (`/dists/trixie/Release`),
  preserved source paths, and all Omnixys files.
- Remastering uses a cross-image xorriso update (`-indev SOURCE -outdev OUTPUT -boot_image any
  replay -update_r`) with El Torito replay, which keeps BIOS/EFI boot structures intact on
  amd64 and arm64 without growing the source image in place.

### Installer media and identity labels

These labels identify different things and are intentionally independent:

- The hardware boot-menu name (for example `UEFI: INTENSO`) is supplied by the USB device and cannot be changed by the ISO.
- The installer ISO Volume ID is derived from `INSTALLER_VERSION` (for example `OMNIXYS121`).
- The boot menu shows `Omnixys Debian Installer <INSTALLER_VERSION>` and its two main options are `Install Omnixys (graphical)` and `Install Omnixys`.
- The separate identity USB keeps its filesystem label from `IDENTITY_DEVICE_LABEL` (normally `OMNIXYS_ID`).

### Identity USB requirements

The identity stick must be a single partition with filesystem label exactly matching the
profile value (`OMNIXYS_ID`, e.g. created with `mkfs.vfat -n OMNIXYS_ID`). The early script
refuses to mount a by-label device whose resolved backing node equals the install medium and
falls back to embedded identity when configured. Retry behavior is controlled by
`OMNIXYS_IDENTITY_RETRIES` / `OMNIXYS_IDENTITY_RETRY_DELAY` header overrides in the
generated script (defaults suit physical media spin-up delays).
