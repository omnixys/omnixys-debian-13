# Changelog

## [1.4.3](https://github.com/omnixys/omnixys-debian-13/compare/v1.4.2...v1.4.3) (2026-07-27)


### Bug Fixes

* **installer:** auto-set grub bootdev from selected target disk ([8c1acf5](https://github.com/omnixys/omnixys-debian-13/commit/8c1acf53e7cf274f0223e80437d15e3312600780))

## [1.4.2](https://github.com/omnixys/omnixys-debian-13/compare/v1.4.1...v1.4.2) (2026-07-27)


### Bug Fixes

* **installer:** remove unused disk early command assignments ([707e642](https://github.com/omnixys/omnixys-debian-13/commit/707e6424f99d52357ab17f5aeedb24919ed81c1a))

## [1.4.1](https://github.com/omnixys/omnixys-debian-13/compare/v1.4.0...v1.4.1) (2026-07-27)


### Bug Fixes

* **installer:** avoid invalid auto disk debconf bootstrap ([c46b99d](https://github.com/omnixys/omnixys-debian-13/commit/c46b99daf918dd69c5185b474d89a8b5caddb90f))
* **installer:** isolate early command into stable wrapper script ([1024546](https://github.com/omnixys/omnixys-debian-13/commit/1024546ea45b5c960c174387438a1755bf4fc158))

## [1.4.0](https://github.com/omnixys/omnixys-debian-13/compare/v1.3.2...v1.4.0) (2026-07-27)


### Features

* **build:** generate amd64 and arm64 iso artifacts ([639df9a](https://github.com/omnixys/omnixys-debian-13/commit/639df9ada5b800a63ddf4f6324d80d6b78a83ee2))


### Bug Fixes

* **ci:** prevent release-please stale branch creation failures ([148fd2a](https://github.com/omnixys/omnixys-debian-13/commit/148fd2a9637c493ada6a19e11988213eed1f7560))
* **config:** use auto disk mode for production installs ([8831e2f](https://github.com/omnixys/omnixys-debian-13/commit/8831e2f91161178869ac28fbb8af52f1705d3e96))
* **installer:** align ssh provisioning with runtime identity ([a97b8fe](https://github.com/omnixys/omnixys-debian-13/commit/a97b8fe1788087fcc5d24f2e405ea0b3c2452035))
* **installer:** harden auto disk detection in early command ([779db14](https://github.com/omnixys/omnixys-debian-13/commit/779db1490380f25ea9d3fef866afef67540bfd5b))
* **installer:** rewrite auto disk early command as POSIX helper script ([f070efe](https://github.com/omnixys/omnixys-debian-13/commit/f070efe8827aadfc3b74d789bbfd18ffa9f19fc6))

## [1.3.2](https://github.com/omnixys/omnixys-debian-13/compare/v1.3.1...v1.3.2) (2026-07-26)


### Bug Fixes

* **product:** Update production.env ([0943045](https://github.com/omnixys/omnixys-debian-13/commit/0943045d14c896506e6a88ead8f919ac2030f159))
* **prod:** update prod.env ([a93ae69](https://github.com/omnixys/omnixys-debian-13/commit/a93ae69c0f953cc6a0f7cfcb994a4abd8af50dc5))

## [1.3.1](https://github.com/omnixys/omnixys-debian-13/compare/v1.3.0...v1.3.1) (2026-07-26)


### Bug Fixes

* **installer:** remove stray validator text ([97682c7](https://github.com/omnixys/omnixys-debian-13/commit/97682c7396fac3a3937fd532261ba322f11357ea))
* **installer:** restore validator syntax ([0771080](https://github.com/omnixys/omnixys-debian-13/commit/07710806dced0b951c18dd18541d0a7f00d8491c))
* **kp:** validator ([6f58bf3](https://github.com/omnixys/omnixys-debian-13/commit/6f58bf3641e4855ba3482f1b4e3ec058555fd003))

## [1.3.0](https://github.com/omnixys/omnixys-debian-13/compare/1.2.0...v1.3.0) (2026-07-26)


### Features

* **installer:** add runtime identity env override ([1edc7dd](https://github.com/omnixys/omnixys-debian-13/commit/1edc7ddb1d3a0520e18a3022650dc4e4c94e25ed))
* **tools:** add identity env generator ([50a75c5](https://github.com/omnixys/omnixys-debian-13/commit/50a75c591b8120c70d98292d9d532fafc995e25c))


### Bug Fixes

* **ci:** use unprefixed workflow secret names ([8261fdc](https://github.com/omnixys/omnixys-debian-13/commit/8261fdc5b19c00dd677f7502321a474e281ab173))
* **config:** make domain optional ([6946400](https://github.com/omnixys/omnixys-debian-13/commit/694640092e8d3656d57c56a61cc80b18a8f614fa))

## [1.2.0](https://github.com/omnixys/omnixys-debian-13/compare/v1.1.0...v1.2.0) (2026-07-26)


### Features

* **installer:** add safe target disk modes for preseed ([767ba2b](https://github.com/omnixys/omnixys-debian-13/commit/767ba2bc3ba45cf3e82f43738f45e973ba3a8c50))


### Bug Fixes

* **release:** publish iso assets on tag push ([fedb8d8](https://github.com/omnixys/omnixys-debian-13/commit/fedb8d897b271f60690841484d0c2db9271b4b46))

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
