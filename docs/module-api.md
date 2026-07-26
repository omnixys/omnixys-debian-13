# Module API

Each feature module lives under modules/<name>/ and includes:

- module.sh
- manifest.yaml
- README.md (recommended)

Recommended manifest fields:

- name
- version
- enabledByDefault
- priority
- dependencies

Execution contract:

- build orchestrator calls: bash module.sh <phase> <repo_root>
- Typical phases: pre-build, post-build
- Module must be idempotent and fail-fast on fatal errors.
