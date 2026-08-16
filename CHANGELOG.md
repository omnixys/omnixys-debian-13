# 🧾 Changelog

All notable changes in this project will be documented in this file.


## 1.0.0 (2026-08-16)

### Build

* **Build:** generate amd64 and arm64 iso artifacts ([](https://github.com/omnixys/omnixys-debian-13/commit/639df9ada5b800a63ddf4f6324d80d6b78a83ee2))

### Builder

* **Builder:** harden Debian ISO download against mirror flakiness ([](https://github.com/omnixys/omnixys-debian-13/commit/7e05799a12566d47fb68ad4941b5cad5d6ae875b))

### Chown

* **Chown:**  build.sh Ausführbar machen ([](https://github.com/omnixys/omnixys-debian-13/commit/8369dbbb8884e14c56f7eef39768e87845b402b7))

### Ci

* **Ci:** migrate release automation to semantic-release ([](https://github.com/omnixys/omnixys-debian-13/commit/1d79c09232f4159f57ca69086e08d0c3930c16e0))
* **Ci:** add pre-merge release gate for release-please PRs ([](https://github.com/omnixys/omnixys-debian-13/commit/a195422c8d17aaf42f6f0a8db17a07c6a2c5974e))
* **Ci:** add semver release automation, nightly channel, and ISO artifacts ([](https://github.com/omnixys/omnixys-debian-13/commit/1660d40fbf5fcec9747135aa5e4fc8310a109779))
* **Ci:** add sudo flag to profiles and harden ISO download retries ([](https://github.com/omnixys/omnixys-debian-13/commit/8a08e3f6b7dc75c141e61802cf3731c3fd1c3097))
* **Ci:** align profile passwords with validator policy ([](https://github.com/omnixys/omnixys-debian-13/commit/a5f41221bdd3fe675840d995d8be6f2120657153))
* **Ci:** annotate sourced shell files to resolve SC1091 ([](https://github.com/omnixys/omnixys-debian-13/commit/3e9019befa824194309096f8d5367a0cd64fff78))
* **Ci:** install xorriso and build deps in test-iso job ([](https://github.com/omnixys/omnixys-debian-13/commit/4996de23cb7c29eb01bb62cd663c7a8562e39656))
* **Ci:** migrate release-please action and clean config warnings ([](https://github.com/omnixys/omnixys-debian-13/commit/862a030b64d2af7040d78ea87f4858518233a1f8))
* **Ci:** prevent release-please stale branch creation failures ([](https://github.com/omnixys/omnixys-debian-13/commit/148fd2a9637c493ada6a19e11988213eed1f7560))
* **Ci:** quote fullname values in profile env files ([](https://github.com/omnixys/omnixys-debian-13/commit/e957076878ab80064f7e88b8ecdf810ce1591774))
* **Ci:** resolve shellcheck warnings in backend and ssh module ([](https://github.com/omnixys/omnixys-debian-13/commit/2949fa6bb0a67a94a0f1fbe168455920ed4188c6))
* **Ci:** suppress SC1091 for dynamic library sourcing in build script ([](https://github.com/omnixys/omnixys-debian-13/commit/26e405bf7c7a3b3b9caf1680cbb17ec858e8746d))
* **Ci:** use unprefixed workflow secret names ([](https://github.com/omnixys/omnixys-debian-13/commit/8261fdc5b19c00dd677f7502321a474e281ab173))

### Config

* **Config:** add production hardening baseline and iso pinning keys ([](https://github.com/omnixys/omnixys-debian-13/commit/c9fa2c34a194faaa60a14b5f151b142767aaecef))
* **Config:** make domain optional ([](https://github.com/omnixys/omnixys-debian-13/commit/694640092e8d3656d57c56a61cc80b18a8f614fa))
* **Config:** use auto disk mode for production installs ([](https://github.com/omnixys/omnixys-debian-13/commit/8831e2f91161178869ac28fbb8af52f1705d3e96))

### Debian-preseed

* **Debian-preseed:** handle empty disk info and register sudo toggle key ([](https://github.com/omnixys/omnixys-debian-13/commit/fc504a538f93892b160cbea96630637496231be8))

### Deps

* **Deps:** add chalk ([](https://github.com/omnixys/omnixys-debian-13/commit/14d7641411f41f771c4d3617d10f00fc41c26080))

### Dry-run

* **Dry-run:** do not require xorriso during validation ([](https://github.com/omnixys/omnixys-debian-13/commit/72eb65f7b6cdb9fa9611188e13af22ca0694608d))

### Identity

* **Identity:** enable dynamic VM provisioning ([](https://github.com/omnixys/omnixys-debian-13/commit/5626b8db0b8b56779efdcaf0cb1faf2a7acbb917))
* **Identity:** prioritize USB identity and persist early diagnostics ([](https://github.com/omnixys/omnixys-debian-13/commit/c228b2ad6163ce285371adc8bae890f6990e3687))
* **Identity:** enable dynamic VM provisioning ([](https://github.com/omnixys/omnixys-debian-13/commit/78caeea4be51ca4b1c972f96c0f64ed3fb598b4e))

### Installer

* **Installer:** add optional sudo nopasswd and runtime upgrade/reboot controls ([](https://github.com/omnixys/omnixys-debian-13/commit/00e3b966f0c5ceb60f7113a3a1f3965b592ee433))
* **Installer:** add runtime identity env override ([](https://github.com/omnixys/omnixys-debian-13/commit/1edc7ddb1d3a0520e18a3022650dc4e4c94e25ed))
* **Installer:** add safe target disk modes for preseed ([](https://github.com/omnixys/omnixys-debian-13/commit/767ba2bc3ba45cf3e82f43738f45e973ba3a8c50))
* **Installer:** guarantee identity-free published VM release images ([](https://github.com/omnixys/omnixys-debian-13/commit/2c4c4ab2b06838cb0b12a01e5b511a000fb58c2b))
* **Installer:** align ssh provisioning with runtime identity ([](https://github.com/omnixys/omnixys-debian-13/commit/a97b8fe1788087fcc5d24f2e405ea0b3c2452035))
* **Installer:** auto-set grub bootdev from selected target disk ([](https://github.com/omnixys/omnixys-debian-13/commit/8c1acf53e7cf274f0223e80437d15e3312600780))
* **Installer:** avoid invalid auto disk debconf bootstrap ([](https://github.com/omnixys/omnixys-debian-13/commit/c46b99daf918dd69c5185b474d89a8b5caddb90f))
* **Installer:** eject install media before reboot to avoid loop ([](https://github.com/omnixys/omnixys-debian-13/commit/8de4ec30f3e367f28191cc7d57da4438c140c2ea))
* **Installer:** harden auto disk detection in early command ([](https://github.com/omnixys/omnixys-debian-13/commit/779db1490380f25ea9d3fef866afef67540bfd5b))
* **Installer:** identity pipeline and USB label fixes ([](https://github.com/omnixys/omnixys-debian-13/commit/2f5aeda2a830a36d39d880bfa3d1e7b14fb8e6f8))
* **Installer:** isolate early command into stable wrapper script ([](https://github.com/omnixys/omnixys-debian-13/commit/1024546ea45b5c960c174387438a1755bf4fc158))
* **Installer:** remove stray validator text ([](https://github.com/omnixys/omnixys-debian-13/commit/97682c7396fac3a3937fd532261ba322f11357ea))
* **Installer:** remove unused disk early command assignments ([](https://github.com/omnixys/omnixys-debian-13/commit/707e6424f99d52357ab17f5aeedb24919ed81c1a))
* **Installer:** restore validator syntax ([](https://github.com/omnixys/omnixys-debian-13/commit/07710806dced0b951c18dd18541d0a7f00d8491c))
* **Installer:** rewrite auto disk early command as POSIX helper script ([](https://github.com/omnixys/omnixys-debian-13/commit/f070efe8827aadfc3b74d789bbfd18ffa9f19fc6))

### Kp

* **Kp:** validator ([](https://github.com/omnixys/omnixys-debian-13/commit/6f58bf3641e4855ba3482f1b4e3ec058555fd003))

### Main

* **Main:** release 1.1.0 ([](https://github.com/omnixys/omnixys-debian-13/commit/3f76b66c4b3f4637a43ae26001137de2f5362a0f))
* **Main:** release 1.2.0 ([](https://github.com/omnixys/omnixys-debian-13/commit/5dff0c033896830a7e884b48cc0dd27fc88d54e2))
* **Main:** release 1.3.0 ([](https://github.com/omnixys/omnixys-debian-13/commit/2ea2c0ab786c46b44360d49ea636dde6986b7d6e))
* **Main:** release 1.3.1 ([](https://github.com/omnixys/omnixys-debian-13/commit/2bbdc9ebc73d61d85018edbaab6f43d84330053e))
* **Main:** release 1.3.2 ([](https://github.com/omnixys/omnixys-debian-13/commit/f332dbf15432ed206e92cfb0d03c6bef61b27ed0))
* **Main:** release 1.4.0 ([](https://github.com/omnixys/omnixys-debian-13/commit/2fe04bdcfb769e0c33d4e81c10feaae8b9ca1b5e))
* **Main:** release 1.4.1 ([](https://github.com/omnixys/omnixys-debian-13/commit/8a5980bce5be8b29e9459d29ce9400d2adc8bc80))
* **Main:** release 1.4.2 ([](https://github.com/omnixys/omnixys-debian-13/commit/e87495d6656bf3dd610c6bc16a3fe9a45a6e0b24))
* **Main:** release 1.4.3 ([](https://github.com/omnixys/omnixys-debian-13/commit/ba325e8eeea7a137f44286a17aec37c869990f2d))
* **Main:** release 1.4.4 ([](https://github.com/omnixys/omnixys-debian-13/commit/0c9f8d24fbe7d81969bd72482c4befa28af7d11d))
* **Main:** release 1.5.0 ([](https://github.com/omnixys/omnixys-debian-13/commit/81d8cde934829ed0e6a373cb8dd87dd55a7b7f46))
* **Main:** release 1.5.1 ([](https://github.com/omnixys/omnixys-debian-13/commit/67fc105a6569007f4315df92d8272b2d22088496))

### Other

* **Other:** add v1.0 acceptance checklist for debian-preseed delivery gate ([](https://github.com/omnixys/omnixys-debian-13/commit/608a4cb8c95ea7960219fdc3ce6e7da9a3fac9b1))
* **Other:** scaffold installer framework and implement debian-preseed remaster flow ([](https://github.com/omnixys/omnixys-debian-13/commit/1b65e4eb1fb13a3b5e52b917d521eef64af38c0b))
* **Other:** init ([](https://github.com/omnixys/omnixys-debian-13/commit/d455089e2ae482cdf055653c414ab32461d0bf5e))
* **Other:** Initial commit ([](https://github.com/omnixys/omnixys-debian-13/commit/524a0ff45252e31cecabd0e133e9eebc28c7a73e))
* **Other:** Merge branch 'main' of https://github.com/omnixys/omnixys-debian-13 ([](https://github.com/omnixys/omnixys-debian-13/commit/4f439423ef52e693089eb5b9846cf3c3aa54e34a))
* **Other:** Merge branch 'main' of https://github.com/omnixys/omnixys-debian-13 ([](https://github.com/omnixys/omnixys-debian-13/commit/45c9939f006c4e1dc101f584eef52c6322a0dd8b))
* **Other:** Merge pull request #1 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/7acd1cb2370970f1bba1c2cbc34a93d4a0a2f0d2)), closes [#1](https://github.com/omnixys/omnixys-debian-13/issues/1)
* **Other:** Merge pull request #10 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/7c36379815fb3ea6331a9255b03b00a4e35aa942)), closes [#10](https://github.com/omnixys/omnixys-debian-13/issues/10)
* **Other:** Merge pull request #11 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/69224277df833dd5e3cef693c4003470300cef69)), closes [#11](https://github.com/omnixys/omnixys-debian-13/issues/11)
* **Other:** Merge pull request #12 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/0be5c8f55c5dc2d1059c5aaf922e14def036a2f1)), closes [#12](https://github.com/omnixys/omnixys-debian-13/issues/12)
* **Other:** Merge pull request #2 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/0e74da284460958cd830b7daa765c2a4a9e722ba)), closes [#2](https://github.com/omnixys/omnixys-debian-13/issues/2)
* **Other:** Merge pull request #3 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/94ec17c12378c76769b47d63138d7069812950c1)), closes [#3](https://github.com/omnixys/omnixys-debian-13/issues/3)
* **Other:** Merge pull request #4 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/8f38cc9bb3e1a2bb080407b8cf61ec99c49a3f6a)), closes [#4](https://github.com/omnixys/omnixys-debian-13/issues/4)
* **Other:** Merge pull request #5 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/50b48f7150a3882e53f8224875754b5785b7c702)), closes [#5](https://github.com/omnixys/omnixys-debian-13/issues/5)
* **Other:** Merge pull request #6 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/58071a49a357e467d2d64e7af4a017647db3fe6b)), closes [#6](https://github.com/omnixys/omnixys-debian-13/issues/6)
* **Other:** Merge pull request #7 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/abc1b5a5e232f6e239d4caa476e731349710ccca)), closes [#7](https://github.com/omnixys/omnixys-debian-13/issues/7)
* **Other:** Merge pull request #8 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/85227f84d7206f551a57c62c7d4bca59ddc3afd3)), closes [#8](https://github.com/omnixys/omnixys-debian-13/issues/8)
* **Other:** Merge pull request #9 from omnixys/release-please--branches--main ([](https://github.com/omnixys/omnixys-debian-13/commit/e5e1f817d736a3ad0ab47ed0c66e8b0bd1257964)), closes [#9](https://github.com/omnixys/omnixys-debian-13/issues/9)
* **Other:** release ([](https://github.com/omnixys/omnixys-debian-13/commit/cdc62c19ad1e94c3d8946fb37616eb38973f9b9d))
* **Other:** Update .gitignore ([](https://github.com/omnixys/omnixys-debian-13/commit/f8cf4a14c1bfb434d708e690812f477b476be875))
* **Other:** Update release.config.mjs ([](https://github.com/omnixys/omnixys-debian-13/commit/c493b5d6253c9cc613e8977f645deaa605254f78))
* **Other:** add boot smoke workflows and config schema migration checks ([](https://github.com/omnixys/omnixys-debian-13/commit/6b5880280ff20228afb23496447cdfdd061ad382))

### Package

* **Package:** make extracted ISO tree writable before boot patching ([](https://github.com/omnixys/omnixys-debian-13/commit/2174227ae2ee2983233c4b16bab639424c353865))
* **Package:** unlock previous ISO tree before cleanup on macOS ([](https://github.com/omnixys/omnixys-debian-13/commit/17537851d3b435c1cc1c413ab95d5e26b6cc40f5))

### Prod

* **Prod:** update prod.env ([](https://github.com/omnixys/omnixys-debian-13/commit/a93ae69c0f953cc6a0f7cfcb994a4abd8af50dc5))

### Product

* **Product:** Update production.env ([](https://github.com/omnixys/omnixys-debian-13/commit/0943045d14c896506e6a88ead8f919ac2030f159))

### Release

* **Release:** 1.0.0 [skip ci] ([](https://github.com/omnixys/omnixys-debian-13/commit/2e8409fba4194870b7d471472d90060110a6cb8d))
* **Release:** 1.0.1 [skip ci] ([](https://github.com/omnixys/omnixys-debian-13/commit/e5b6195b6c99aaa7adaf52fd039f724fbdaffc87))
* **Release:** 1.1.0 [skip ci] ([](https://github.com/omnixys/omnixys-debian-13/commit/b355d135814a560f8a71705298601976b6be448a))
* **Release:** 1.1.1 [skip ci] ([](https://github.com/omnixys/omnixys-debian-13/commit/26e4f34dd0f373523edac068a620284a20296979))
* **Release:** 1.2.0 [skip ci] ([](https://github.com/omnixys/omnixys-debian-13/commit/47d8dfec846dac4d242aee95619c2b69c5c4c61b))
* **Release:** 1.2.1 [skip ci] ([](https://github.com/omnixys/omnixys-debian-13/commit/8ee821e2e6ca1a88ee409888adcd0a4146d498a5))
* **Release:** 1.3.0 [skip ci] ([](https://github.com/omnixys/omnixys-debian-13/commit/0d266fe857a3366fe489900e9f9cb8d5bcc8edd7))
* **Release:** 1.3.1 [skip ci] ([](https://github.com/omnixys/omnixys-debian-13/commit/02c8315f174fe25daa7116e49aa6669afad4ebb1))
* **Release:** reset changelog for fresh 1.0.0 start ([](https://github.com/omnixys/omnixys-debian-13/commit/b7045813d8a3c1266808fff45986926ab09b70c7))
* **Release:** publish only iso + sha256 assets ([](https://github.com/omnixys/omnixys-debian-13/commit/8783b0a8fb2644a746d6be16da8d0c8291f64195))
* **Release:** publish dedicated VM installation images ([](https://github.com/omnixys/omnixys-debian-13/commit/9a9dd9ceb52ccd80b8165faf8393c9591c781087))
* **Release:** publish iso assets on tag push ([](https://github.com/omnixys/omnixys-debian-13/commit/fedb8d897b271f60690841484d0c2db9271b4b46))

### Shellcheck

* **Shellcheck:** resolve SC2155 in log helper ([](https://github.com/omnixys/omnixys-debian-13/commit/8be6edfdaf4f070668a235ceefcb1210dda3b138))

### Tools

* **Tools:** add identity env generator ([](https://github.com/omnixys/omnixys-debian-13/commit/50a75c591b8120c70d98292d9d532fafc995e25c))

### Validator

* **Validator:** disable password strength validation ([](https://github.com/omnixys/omnixys-debian-13/commit/a8f8835531e9d3ec1873ed65b2c37bd5871bc776))

### Verify

* **Verify:** resolve exact ISO checksum entry and improve mismatch diagnostics ([](https://github.com/omnixys/omnixys-debian-13/commit/6b1a581bd979f0648c1d9ef26953167691673bd1))

### Vm

* **Vm:** change defaults ([](https://github.com/omnixys/omnixys-debian-13/commit/14f6fc097109335df845ed3c1230ddba4edb084c))
* **Vm:** publish only iso + sha256 assets ([](https://github.com/omnixys/omnixys-debian-13/commit/11fdeb3621255d772b4fb5d07c0ff3e418b4ac01))

### Workflow

* **Workflow:** remove nightly ISO release channel ([](https://github.com/omnixys/omnixys-debian-13/commit/ce8cefc62d393bf70367277653f2ce12676642c9))
* **Workflow:** use OMNIXYS_TOKEN for semantic-release ([](https://github.com/omnixys/omnixys-debian-13/commit/42b8c322f5dda28f126d98ae9f0470a6498793d1))
