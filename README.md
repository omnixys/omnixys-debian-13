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
`INSTALL_FIRMWARE=false`) and are marked with `"profile": "vm"` in their
`.build-info.json`, so they can be distinguished machine-readably from the
production artifacts. Use the `-vm` image for UTM/ARM64 VM installs, or build
manually:

```bash
./build.sh --config configs/vm.env --arches amd64,arm64
```

`-vm` images (and local VM builds from `configs/vm.env`) use the same `usb-env`
identity provisioning as the production images, but with `IDENTITY_REQUIRED=false`:
identity values are applied when present, otherwise the VM build-time defaults are
used. To provision a VM dynamically, attach a volume/USB with the `OMNIXYS_ID`
label containing `identity.env`, or bake `./identity.env` into the ISO at build time
(see "Runtime Identity Override"). Network configuration stays DHCP; no
VM-specific static IP is enforced.

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
- `semantic-release.yml`: automatic SemVer releases directly on `main` pushes (tag + GitHub Release + changelog)
- `release.yml`: release asset builder (`.iso`, `.sha256`, `.sha512`, `build-info.json`, `sbom.cdx.json`) for production and `-vm` images

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

Every push to `main` is automatically released with semantic-release:

1. `semantic-release.yml` determines the next version from Conventional Commits and creates the tag + GitHub Release.
2. `release.yml` builds the production and `-vm` ISOs and attaches all assets to the release.

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
- Supported variables in `identity.env` are:
- `OMNIXYS_HOSTNAME`
- `OMNIXYS_DOMAIN` (optional)
- `OMNIXYS_FULLNAME`
- `OMNIXYS_USERNAME`
- `OMNIXYS_SSH_PUBLIC_KEY` (optional)
- `OMNIXYS_PASSWORD_HASH`

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

Network configuration is unaffected: the installer always uses DHCP, so no static IP is enforced for bare metal or VMs.

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
