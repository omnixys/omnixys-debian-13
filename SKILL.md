<!-- repository: projects/omnixys-debian-13 | kind: PROJECT_INSTALLER | stack: installer -->

# omnixys-debian-13 — Skill: Installer Development

> Workflow for omnixys-debian-13 (projects/omnixys-debian-13). Execute this workflow before, during, and
> after changes in this repository.

## Repository Facts

- Kind: Installer
- Package: `omnixys-debian-13` (version: 1.0.0)
- Runtime: bash + Node (pnpm) — Debian 13 installer framework
- Description: Omnixys Debian 13 installer framework (bash modules + Node tooling, semantic-release, commitlint).
- Architecture: core/lib, modules/{ansible, core, custom, docker, k3s, ssh, tailscale}, installer/, plugins/, hooks/, templates/, scripts/, configs/
- Database: n/a; Migrations: n/a
- API: n/a
- Messaging: n/a
- Tests: tests/ directory present (framework-specific); no unit runner defined


## Workflow

### 1. Understand the change

- This is the Omnixys Debian 13 installer framework (bash + Node). It is NOT a Next.js
  or service repository.
- Modules live under `core/lib, modules/{ansible, core, custom, docker, k3s, ssh, tailscale}, installer/, plugins/, hooks/, templates/, scripts/, configs/`; never expose
  `config.env`/`identity.env` values in logs or documentation.

### 2. Implement

- Follow the established module layout and hook/plugin conventions.
- Keep installer steps idempotent and re-runnable on Debian 13.
- Never run the destructive `build.sh` against a real system as part of validation.

### 3. Validate

  - Validate modified bash with `bash -n` and review shellcheck findings where available.
  - Record all results as `PASS`/`FAIL`/`PRE-EXISTING FAILURE`/`NOT RUN` with reasons.

## Commit

- Conventional Commits; stage only intended files; never push.
