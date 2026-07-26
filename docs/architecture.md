# Architecture

Layers:

1. Core (installer-agnostic orchestration)
2. Installer backends (debian-preseed in v1)
3. Feature modules
4. Hooks
5. Plugins

Rule:

- New features should integrate through backend/module/hook/plugin contracts.
- Core should avoid distro-specific logic.
