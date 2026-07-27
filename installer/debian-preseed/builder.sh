#!/usr/bin/env bash

debian_prepare_paths() {
  CACHE_DIR="$ROOT_DIR/cache/debian-preseed"
  ARTIFACTS_DIR="$ROOT_DIR/artifacts"
  BACKEND_WORK_DIR="$ROOT_DIR/work/debian-preseed"
  ISO_TREE_DIR="$BACKEND_WORK_DIR/iso-tree"
  GENERATED_DIR="$BACKEND_WORK_DIR/generated"

  ensure_dir "$ROOT_DIR/downloads"
  ensure_dir "$ROOT_DIR/cache"
  ensure_dir "$CACHE_DIR"
  ensure_dir "$ARTIFACTS_DIR"
  ensure_dir "$BACKEND_WORK_DIR"
}

debian_resolve_iso_url() {
  if [[ -n "${DEBIAN_ISO_URL:-}" ]]; then
    echo "$DEBIAN_ISO_URL"
    return 0
  fi

  local base="https://cdimage.debian.org/debian-cd/current/${ARCH}/iso-cd/"
  local listing

  if command -v curl >/dev/null 2>&1; then
    listing="$(curl -fsSL "$base" || true)"
  elif command -v wget >/dev/null 2>&1; then
    listing="$(wget -q -O - "$base" || true)"
  else
    die "Either curl or wget is required to resolve Debian ISO URL"
  fi

  local match
  match="$(printf '%s' "$listing" | grep -Eo "debian-[0-9.]+-${ARCH}-netinst\.iso" | sort -V | tail -n 1 || true)"
  [[ -n "$match" ]] || die "Could not resolve Debian netinst ISO for ARCH=${ARCH}"
  echo "$base$match"
}

debian_build() {
  debian_prepare_paths

  ISO_URL="$(debian_resolve_iso_url)"
  ISO_FILE_NAME="$(basename "$ISO_URL")"
  ISO_SOURCE_PATH="$ROOT_DIR/downloads/$ISO_FILE_NAME"

  info "Resolved ISO URL: $ISO_URL"
  info "Resolved ISO file: $ISO_SOURCE_PATH"

  if [[ -f "$ISO_SOURCE_PATH" ]]; then
    info "ISO already present in downloads"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] would download ISO to $ISO_SOURCE_PATH"
    return 0
  fi

  step "Downloading Debian ISO"
  if command -v curl >/dev/null 2>&1; then
    if ! run_cmd curl -fL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 --max-time 0 "$ISO_URL" -o "$ISO_SOURCE_PATH"; then
      warn "curl download failed, retrying with wget fallback"
      run_cmd wget --tries=5 --waitretry=3 --timeout=20 -O "$ISO_SOURCE_PATH" "$ISO_URL"
    fi
  else
    run_cmd wget --tries=5 --waitretry=3 --timeout=20 -O "$ISO_SOURCE_PATH" "$ISO_URL"
  fi
}

debian_read_disk_info() {
  local tmp_info line
  tmp_info="$BACKEND_WORK_DIR/.disk-info"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "Debian (dry-run)"
    return 0
  fi

  run_cmd xorriso -osirrox on -indev "$ISO_SOURCE_PATH" -extract /.disk/info "$tmp_info" >/dev/null 2>&1 || true
  if [[ -s "$tmp_info" ]]; then
    line="$(head -n 1 "$tmp_info" | tr -d '\r')"
    [[ -n "$line" ]] && echo "$line" || echo "unknown"
  else
    echo "unknown"
  fi
}

debian_resolve_sha_from_upstream() {
  local base sumfile resolved
  base="$(dirname "$ISO_URL")"
  sumfile="$BACKEND_WORK_DIR/SHA256SUMS"

  if [[ "$DRY_RUN" == "true" ]]; then
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$base/SHA256SUMS" -o "$sumfile" || return 1
  else
    wget -q -O "$sumfile" "$base/SHA256SUMS" || return 1
  fi

  # Match the exact ISO filename only (avoid suffix collisions like .torrent/.jigdo)
  resolved="$(awk -v f="$ISO_FILE_NAME" '
    $2 == f { print $1; exit }
    $2 == "*" f { print $1; exit }
  ' "$sumfile")"
  [[ -n "$resolved" ]] || return 1
  printf '%s' "$resolved"
}

debian_verify() {
  [[ -n "${ISO_SOURCE_PATH:-}" ]] || die "ISO_SOURCE_PATH is unset, build() must run before verify()"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] verify step completed"
    return 0
  fi

  [[ -f "$ISO_SOURCE_PATH" ]] || die "Source ISO not found: $ISO_SOURCE_PATH"

  local disk_info
  disk_info="$(debian_read_disk_info)"
  info "ISO identity: $disk_info"

  if [[ "$disk_info" != "unknown" ]] && [[ "$disk_info" != *Debian* ]]; then
    die "Source ISO does not look like Debian: $disk_info"
  fi

  local expected_sha
  expected_sha="${DEBIAN_ISO_SHA256:-}"
  if [[ -z "$expected_sha" ]]; then
    expected_sha="$(debian_resolve_sha_from_upstream || true)"
    if [[ -n "$expected_sha" ]]; then
      info "Resolved source ISO SHA256 from upstream index"
    fi
  fi

  if [[ -n "$expected_sha" ]]; then
    step "Verifying source ISO SHA256"
    local actual
    actual="$(sha256sum "$ISO_SOURCE_PATH" | awk '{print $1}')"
    expected_sha="${expected_sha,,}"
    actual="${actual,,}"
    if [[ "$actual" != "$expected_sha" ]]; then
      die "ISO SHA256 mismatch (expected: $expected_sha, actual: $actual). Remove cached ISO and rerun: rm -f '$ISO_SOURCE_PATH'"
    fi
    printf '%s  %s\n' "$actual" "$ISO_FILE_NAME" >"$ARTIFACTS_DIR/source.${ARCH}.iso.sha256"
  else
    warn "DEBIAN_ISO_SHA256 not set; checksum verification skipped"
  fi
}

debian_patch_boot_configs() {
  local target_dir="$1"
  local params
  params="$(debian_boot_params | tr '\n' ' ' | sed 's/  */ /g')"

  patch_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0

    awk -v params="$params" '
      {
        line = $0
        if ((line ~ /(^|[[:space:]])linux[[:space:]]/ || line ~ /(^|[[:space:]])append[[:space:]]/) && line ~ /---/ && line !~ /auto=true/) {
          sub(/ ---/, " " params " ---", line)
        }
        print line
      }
    ' "$file" >"$file.tmp"
    mv "$file.tmp" "$file"
  }

  patch_file "$target_dir/boot/grub/grub.cfg"
  patch_file "$target_dir/isolinux/txt.cfg"
  patch_file "$target_dir/isolinux/isolinux.cfg"
}

debian_detect_bootloader_files() {
  local target_dir="$1"
  BOOTLOADER_FILES=()

  [[ -f "$target_dir/boot/grub/grub.cfg" ]] && BOOTLOADER_FILES+=("boot/grub/grub.cfg")
  [[ -f "$target_dir/isolinux/txt.cfg" ]] && BOOTLOADER_FILES+=("isolinux/txt.cfg")
  [[ -f "$target_dir/isolinux/isolinux.cfg" ]] && BOOTLOADER_FILES+=("isolinux/isolinux.cfg")

  if [[ "${#BOOTLOADER_FILES[@]}" -eq 0 ]]; then
    die "No supported bootloader config files found in extracted ISO tree"
  fi

  info "Bootloader config files detected: ${BOOTLOADER_FILES[*]}"
}

debian_extract_iso_tree() {
  local target_dir="$1"

  if [[ -e "$target_dir" ]]; then
    # Previous extracts may contain read-only/immutable files from ISO metadata.
    if command -v chflags >/dev/null 2>&1; then
      run_cmd chflags -R nouchg "$target_dir" >/dev/null 2>&1 || true
    fi
    run_cmd chmod -R u+w "$target_dir" >/dev/null 2>&1 || true
    rm -rf "$target_dir"
  fi

  ensure_dir "$target_dir"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] would extract source ISO into $target_dir"
    return 0
  fi

  step "Extracting source ISO tree"
  run_cmd xorriso -osirrox on -indev "$ISO_SOURCE_PATH" -extract / "$target_dir"

  # Files extracted from ISO can be read-only; make work tree writable for patching.
  run_cmd chmod -R u+w "$target_dir"
}

debian_package() {
  ISO_OUTPUT_PATH="$ROOT_DIR/output/omnixys-debian-${DEBIAN_MAJOR}-${ARCH}-auto.iso"
  local metadata_copy="$ROOT_DIR/logs/install.log"

  ensure_dir "$ROOT_DIR/output"

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] bootloader files to patch: boot/grub/grub.cfg, isolinux/txt.cfg, isolinux/isolinux.cfg"
    info "[dry-run] would package output ISO: $ISO_OUTPUT_PATH"
    return 0
  fi

  [[ -f "$ISO_SOURCE_PATH" ]] || die "Source ISO missing for package step"
  [[ -f "$GENERATED_DIR/preseed.cfg" ]] || die "Generated preseed not found"

  debian_extract_iso_tree "$ISO_TREE_DIR"
  debian_detect_bootloader_files "$ISO_TREE_DIR"

  step "Injecting generated files into ISO tree"
  run_cmd cp "$GENERATED_DIR/preseed.cfg" "$ISO_TREE_DIR/preseed.cfg"
  run_cmd cp "$GENERATED_DIR/installer-info.txt" "$ISO_TREE_DIR/omnixys-installer-info.txt"
  if [[ -f "$GENERATED_DIR/omnixys-early.sh" ]]; then
    run_cmd cp "$GENERATED_DIR/omnixys-early.sh" "$ISO_TREE_DIR/omnixys-early.sh"
    run_cmd chmod 0755 "$ISO_TREE_DIR/omnixys-early.sh"
  fi
  if [[ -f "$GENERATED_DIR/omnixys-disk-detect.sh" ]]; then
    run_cmd cp "$GENERATED_DIR/omnixys-disk-detect.sh" "$ISO_TREE_DIR/omnixys-disk-detect.sh"
    run_cmd chmod 0755 "$ISO_TREE_DIR/omnixys-disk-detect.sh"
  fi

  step "Patching boot configuration"
  debian_patch_boot_configs "$ISO_TREE_DIR"

  step "Rebuilding remastered ISO"
  run_cmd xorriso \
    -indev "$ISO_SOURCE_PATH" \
    -outdev "$ISO_OUTPUT_PATH" \
    -boot_image any replay \
    -update_r "$ISO_TREE_DIR" / \
    -commit \
    -end

  cp "$GENERATED_DIR/installer-info.txt" "$metadata_copy"
  cp "$GENERATED_DIR/installer-info.txt" "$ARTIFACTS_DIR/installer-info.txt"

  step "Generating output SHA256"
  sha256sum "$ISO_OUTPUT_PATH" | tee "$ISO_OUTPUT_PATH.sha256" >/dev/null
  cp "$ISO_OUTPUT_PATH.sha256" "$ARTIFACTS_DIR/output.${ARCH}.iso.sha256"
}
