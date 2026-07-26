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

- `output/omnixys-debian-13-auto.iso`
- `output/omnixys-debian-13-auto.iso.sha256`
- `logs/build.log`
- `logs/install.log`

## CLI

```bash
./build.sh --help
./build.sh --version
./build.sh --dry-run
./build.sh --config configs/homelab.env
```

## Key Configuration

Framework level:

- `CONFIG_SCHEMA_VERSION=1`
- `INSTALLER=debian-preseed`
- `ARCH=amd64`
- `INSTALLER_VERSION=1.0.0`

Debian backend:

- `DEBIAN_MAJOR=13`
- `DEBIAN_RELEASE=stable`
- `DEBIAN_ISO_URL=` (optional override)
- `DEBIAN_ISO_SHA256=` (recommended)

Install behavior:

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

- `ci.yml`: ShellCheck + dry-run + per-push/per-PR ISO artifacts
- `boot-tests.yml`: manual build + BIOS/UEFI smoke tests (matrix-ready backend structure)
- `release-gate.yml`: validates release-please PRs (tests + full ISO build) before merge
- `release-please.yml`: automatic SemVer release PRs and changelog updates from Conventional Commits
- `release.yml`: published release asset builder (`.iso`, `.sha256`, `.sha512`, `build-info.json`, `sbom.cdx.json`)
- `nightly.yml`: daily nightly ISO artifacts and nightly pre-release updates

## Download Channels

- Stable Releases: GitHub Releases assets
- CI Artifacts: per push and pull request workflow artifacts
- Nightly: daily pre-release assets and nightly workflow artifacts

## Conventional Commits and SemVer

Versioning is automated with release-please and Conventional Commits.

- `fix:` -> patch bump
- `feat:` -> minor bump
- `BREAKING CHANGE:` or `!` -> major bump

Example commit types:

- `fix(installer): handle checksum edge case`
- `feat(workflow): add nightly release channel`
- `feat!: change backend API`

Release process note:

- Release PRs created by release-please should pass `release-gate.yml` before merge.
- Merge only after the gate is green, then release publishing workflows can proceed.

## Safety Warning

When disk installation is fully active, settings like `ERASE_DISK=true` will destroy data on target disks.
Always test in VM first.
