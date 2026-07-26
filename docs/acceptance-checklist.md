# v1.0 Acceptance Checklist

## Build and Validation
- [ ] `./build.sh --config <profile> --dry-run` returns success.
- [ ] Readiness report ends with `Ready to build`.
- [ ] Source ISO identity is Debian.
- [ ] Source ISO SHA256 is verified.

## ISO Output
- [ ] Output ISO is produced at `output/omnixys-debian-13-auto.iso`.
- [ ] Output SHA256 file is produced.
- [ ] `preseed.cfg` is embedded into the remastered ISO.
- [ ] Bootloader configs were detected and patched.

## Unattended Install
- [ ] BIOS boot path reaches unattended installer.
- [ ] UEFI boot path reaches unattended installer.
- [ ] No interactive prompts for locale/user/partition steps.
- [ ] Installed system has expected hostname/user/ssh policy.

## Security and Documentation
- [ ] Root login is disabled in installed system.
- [ ] User password is stored as hash in generated preseed only.
- [ ] Secure Boot status is validated and documented.
- [ ] README reflects current delivery status and limitations.
