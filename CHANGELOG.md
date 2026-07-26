# Changelog

## [1.1.0](https://github.com/omnixys/omnixys-debian-13/compare/v1.0.0...v1.1.0) (2026-07-26)


### Features

* **ci:** add pre-merge release gate for release-please PRs ([a195422](https://github.com/omnixys/omnixys-debian-13/commit/a195422c8d17aaf42f6f0a8db17a07c6a2c5974e))
* **ci:** add semver release automation, nightly channel, and ISO artifacts ([1660d40](https://github.com/omnixys/omnixys-debian-13/commit/1660d40fbf5fcec9747135aa5e4fc8310a109779))
* **installer:** add optional sudo nopasswd and runtime upgrade/reboot controls ([00e3b96](https://github.com/omnixys/omnixys-debian-13/commit/00e3b966f0c5ceb60f7113a3a1f3965b592ee433))
* scaffold installer framework and implement debian-preseed remaster flow ([1b65e4e](https://github.com/omnixys/omnixys-debian-13/commit/1b65e4eb1fb13a3b5e52b917d521eef64af38c0b))


### Bug Fixes

* **chown:** build.sh Ausführbar machen ([8369dbb](https://github.com/omnixys/omnixys-debian-13/commit/8369dbbb8884e14c56f7eef39768e87845b402b7))
* **ci:** add sudo flag to profiles and harden ISO download retries ([8a08e3f](https://github.com/omnixys/omnixys-debian-13/commit/8a08e3f6b7dc75c141e61802cf3731c3fd1c3097))
* **ci:** align profile passwords with validator policy ([a5f4122](https://github.com/omnixys/omnixys-debian-13/commit/a5f41221bdd3fe675840d995d8be6f2120657153))
* **ci:** annotate sourced shell files to resolve SC1091 ([3e9019b](https://github.com/omnixys/omnixys-debian-13/commit/3e9019befa824194309096f8d5367a0cd64fff78))
* **ci:** install xorriso and build deps in test-iso job ([4996de2](https://github.com/omnixys/omnixys-debian-13/commit/4996de23cb7c29eb01bb62cd663c7a8562e39656))
* **ci:** migrate release-please action and clean config warnings ([862a030](https://github.com/omnixys/omnixys-debian-13/commit/862a030b64d2af7040d78ea87f4858518233a1f8))
* **ci:** quote fullname values in profile env files ([e957076](https://github.com/omnixys/omnixys-debian-13/commit/e957076878ab80064f7e88b8ecdf810ce1591774))
* **ci:** resolve shellcheck warnings in backend and ssh module ([2949fa6](https://github.com/omnixys/omnixys-debian-13/commit/2949fa6bb0a67a94a0f1fbe168455920ed4188c6))
* **ci:** suppress SC1091 for dynamic library sourcing in build script ([26e405b](https://github.com/omnixys/omnixys-debian-13/commit/26e405bf7c7a3b3b9caf1680cbb17ec858e8746d))
* **debian-preseed:** handle empty disk info and register sudo toggle key ([fc504a5](https://github.com/omnixys/omnixys-debian-13/commit/fc504a538f93892b160cbea96630637496231be8))
* **dry-run:** do not require xorriso during validation ([72eb65f](https://github.com/omnixys/omnixys-debian-13/commit/72eb65f7b6cdb9fa9611188e13af22ca0694608d))
* **package:** make extracted ISO tree writable before boot patching ([2174227](https://github.com/omnixys/omnixys-debian-13/commit/2174227ae2ee2983233c4b16bab639424c353865))
* **package:** unlock previous ISO tree before cleanup on macOS ([1753785](https://github.com/omnixys/omnixys-debian-13/commit/17537851d3b435c1cc1c413ab95d5e26b6cc40f5))
* **shellcheck:** resolve SC2155 in log helper ([8be6edf](https://github.com/omnixys/omnixys-debian-13/commit/8be6edfdaf4f070668a235ceefcb1210dda3b138))
* **verify:** resolve exact ISO checksum entry and improve mismatch diagnostics ([6b1a581](https://github.com/omnixys/omnixys-debian-13/commit/6b1a581bd979f0648c1d9ef26953167691673bd1))

## [1.0.0] - 2026-07-26

- Initial framework scaffolding.
- Installer-agnostic core orchestration.
- Debian Preseed backend skeleton.
- Module, hooks, configs, templates, and CI foundation.
