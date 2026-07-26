# Plugin API

Plugins are external extension packages loaded from plugins/<name>/.

v1 policy:
- Trusted local plugins only.
- No remote plugin download or execution.

Recommended plugin structure:
- manifest.yaml
- backend.sh or module.sh
- README.md

Recommended manifest fields:
- name
- version
- type (backend|module)
- priority
- dependencies
- supportedEvents

Supported build events/hooks:
- pre-build
- post-build
- pre-install
- post-install

Dependency declaration:
- Use a comma-separated list in `dependencies`.
- Dependencies should reference known modules/plugins by name.

Entry point behavior:
- Exit `0` on success.
- Exit non-zero on fatal error.
- Must respect dry-run mode when invoked from the framework.
