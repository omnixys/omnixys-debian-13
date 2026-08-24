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
  local listing err_file fetch_msg
  err_file="$(mktemp)"

  if command -v curl >/dev/null 2>&1; then
    listing="$(curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 "$base" 2>"$err_file")" || true
  elif command -v wget >/dev/null 2>&1; then
    listing="$(wget -q --tries=5 --waitretry=3 -O - "$base" 2>"$err_file")" || true
  else
    die "Either curl or wget is required to resolve Debian ISO URL"
  fi

  local match
  match="$(printf '%s' "$listing" | grep -Eo "debian-[0-9.]+-${ARCH}-netinst\.iso" | sort -V | tail -n 1 || true)"
  fetch_msg="$(<"$err_file")"
  rm -f "$err_file"
  [[ -n "$match" ]] || die "Could not resolve Debian netinst ISO for ARCH=${ARCH} (${fetch_msg:-listing fetch failed})"
  echo "$base$match"
}

debian_build() {
  debian_prepare_paths

  ISO_URL="$(debian_resolve_iso_url)"
  ISO_FILE_NAME="$(basename "$ISO_URL")"
  ISO_SOURCE_PATH="$ROOT_DIR/downloads/$ISO_FILE_NAME"

  info "Resolved ISO URL: $ISO_URL"
  info "Resolved ISO file: $ISO_SOURCE_PATH"

  if [[ -s "$ISO_SOURCE_PATH" ]]; then
    info "ISO already present in downloads"
    return 0
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    info "[dry-run] would download ISO to $ISO_SOURCE_PATH"
    return 0
  fi

  step "Downloading Debian ISO"
  if command -v curl >/dev/null 2>&1; then
    if ! run_cmd curl -fL --retry 8 --retry-delay 3 --retry-all-errors --connect-timeout 20 --speed-limit 1024 --speed-time 60 --max-time 0 "$ISO_URL" -o "$ISO_SOURCE_PATH"; then
      rm -f "$ISO_SOURCE_PATH"
      warn "curl download failed, retrying with wget fallback"
      run_cmd wget --tries=8 --waitretry=3 --timeout=20 -O "$ISO_SOURCE_PATH" "$ISO_URL"
    fi
  else
    run_cmd wget --tries=8 --waitretry=3 --timeout=20 -O "$ISO_SOURCE_PATH" "$ISO_URL"
  fi
  if [[ ! -s "$ISO_SOURCE_PATH" ]]; then
    rm -f "$ISO_SOURCE_PATH"
    die "ISO download failed: no valid ISO file at $ISO_SOURCE_PATH"
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
    curl -fsSL --retry 5 --retry-delay 3 --retry-all-errors --connect-timeout 20 "$base/SHA256SUMS" -o "$sumfile" || return 1
  else
    wget -q --tries=5 --waitretry=3 -O "$sumfile" "$base/SHA256SUMS" || return 1
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

debian_identity_embed_enabled() {
  # IDENTITY_EMBED controls whether a local ./identity.env is baked into the
  # output ISO. It is independent of the runtime usb-env lookup mechanism
  # (IDENTITY_SOURCE/IDENTITY_REQUIRED/IDENTITY_DEVICE_LABEL/OMNIXYS_ID),
  # which is untouched regardless of this value.
  #
  # Default is true to preserve the historic behaviour (local / production
  # builds may embed a self-provisioning identity.env). Published VM release
  # images force IDENTITY_EMBED=false to guarantee no identity is shipped.
  [[ "${IDENTITY_EMBED:-true}" == "true" ]]
}

debian_iso_contains_path() {
  # $1 = ISO path, $2 = ISO path to test (e.g. "/identity.env")
  # xorriso -find prints the entry (quoted) when it exists and nothing when absent.
  local iso="$1" path="$2"
  local listing
  listing="$(run_cmd xorriso -indev "$iso" -find "$path" 2>/dev/null || true)"
  [[ -n "${listing//[[:space:]]\'}" ]]
}

debian_assert_no_identity_in_iso() {
  # Release gate: when IDENTITY_EMBED=false we must guarantee the final
  # ISO does not carry a baked identity.env, independent of whether a local
  # ./identity.env happened to be checked out at build time.
  [[ "$IDENTITY_EMBED" == "false" ]] || return 0
  [[ "$DRY_RUN" == "true" ]] && return 0
  [[ -f "$ISO_OUTPUT_PATH" ]] || return 0

  if debian_iso_contains_path "$ISO_OUTPUT_PATH" "/identity.env"; then
    die "IDENTITY_EMBED=false but /identity.env is present in final ISO: $ISO_OUTPUT_PATH"
  fi
  info "Release gate passed: no /identity.env baked into ISO ($ISO_OUTPUT_PATH)"
}

debian_iso_listing() {
  # $1 = ISO path. Prints sorted absolute paths of every object in the ISO
  # tree. The implicit root entry ("/") is dropped so the output matches
  # debian_tree_listing and comparisons stay deterministic. xorriso quotes
  # entries with single quotes; strip them as well.
  xorriso -indev "$1" -find / -- 2>/dev/null | tr -d "'" | awk 'NF && $0 != "/"' | LC_ALL=C sort
}

debian_tree_listing() {
  # $1 = work-tree directory. Prints sorted absolute paths (leading slash) of
  # every object in the tree, matching debian_iso_listing output format so the
  # two listings can be compared directly.
  ( cd "$1" && LC_ALL=C find . -mindepth 1 -print ) | sed 's|^\./|/|' | tr -d "'" | awk 'NF' | LC_ALL=C sort
}

debian_verify_work_tree_completeness() {
  # Guard against silent remaster corruption: xorriso -update_r mirrors the
  # work tree, i.e. every ISO object without a disk counterpart is DELETED
  # from the image. An incomplete extraction would therefore shrink the
  # installer medium unnoticed. This check refuses to update unless the work
  # tree contains every path of the source ISO, so the update pass can only
  # ever add or refresh Omnixys files.
  [[ "$DRY_RUN" == "true" ]] && return 0

  local tmp_dir total
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/omnixys-tree-check.XXXXXX")"
  tfail() { rm -rf "$tmp_dir"; die "$*"; }

  debian_iso_listing "$ISO_SOURCE_PATH" >"$tmp_dir/src.txt"
  debian_tree_listing "$ISO_TREE_DIR" >"$tmp_dir/tree.txt"

  [[ -s "$tmp_dir/src.txt" ]] || tfail "Work tree check failed: cannot list source ISO: $ISO_SOURCE_PATH"
  [[ -s "$tmp_dir/tree.txt" ]] || tfail "Work tree check failed: work tree is empty: $ISO_TREE_DIR"

  comm -23 "$tmp_dir/src.txt" "$tmp_dir/tree.txt" >"$tmp_dir/missing.txt"
  if [[ -s "$tmp_dir/missing.txt" ]]; then
    total="$(wc -l <"$tmp_dir/missing.txt" | tr -d ' ')"
    {
      echo "Extraction into work tree is incomplete ($total path(s)); refusing to remaster."
      echo "xorriso -update_r would delete these paths from the final ISO:"
      head -n 20 "$tmp_dir/missing.txt"
    } >&2
    tfail "Work tree check failed: $total source path(s) missing from $ISO_TREE_DIR (first: $(head -n 3 "$tmp_dir/missing.txt" | tr '\n' ' '))"
  fi

  rm -rf "$tmp_dir"
  info "Work tree completeness verified: every source ISO path is present"
}

debian_verify_iso_structure() {
  # Structural release gate for the remastered ISO. The final image must:
  #   1. contain every path of the source Debian ISO (remaster extends, never
  #      replaces),
  #   2. keep the Debian repository layout required by debian-installer
  #      (/dists/<suite>/Release, /pool payload, /.disk/info),
  #   3. keep all bootloader configs and injected Omnixys files, where the
  #      injected shell scripts must remain syntactically valid.
  # The suite (e.g. trixie) is derived dynamically from the source listing.
  [[ "$DRY_RUN" == "true" ]] && return 0
  [[ -f "$ISO_SOURCE_PATH" ]] || die "Structure verification failed: source ISO missing: $ISO_SOURCE_PATH"
  [[ -f "$ISO_OUTPUT_PATH" ]] || die "Structure verification failed: output ISO missing: $ISO_OUTPUT_PATH"

  local tmp_dir suite release_path total cfg script_name extract_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/omnixys-iso-verify.XXXXXX")"
  vfail() { rm -rf "$tmp_dir"; die "$*"; }

  debian_iso_listing "$ISO_SOURCE_PATH" >"$tmp_dir/src.txt"
  debian_iso_listing "$ISO_OUTPUT_PATH" >"$tmp_dir/out.txt"

  [[ -s "$tmp_dir/src.txt" ]] || vfail "Structure verification failed: cannot list source ISO: $ISO_SOURCE_PATH"
  [[ -s "$tmp_dir/out.txt" ]] || vfail "Structure verification failed: cannot list output ISO: $ISO_OUTPUT_PATH"

  # 1. Every source path must survive the remaster.
  comm -23 "$tmp_dir/src.txt" "$tmp_dir/out.txt" >"$tmp_dir/missing.txt"
  if [[ -s "$tmp_dir/missing.txt" ]]; then
    total="$(wc -l <"$tmp_dir/missing.txt" | tr -d ' ')"
    {
      echo "Remastered ISO lost content from source ISO ($total path(s)); first entries:"
      head -n 20 "$tmp_dir/missing.txt"
    } >&2
    vfail "Remaster verification failed: $total source path(s) missing from $ISO_OUTPUT_PATH"
  fi

  # 2. Debian installer repository layout must be intact.
  suite="$(awk -F/ '$2 == "dists" && $3 != "" && $4 == "Release" { print $3; exit }' "$tmp_dir/src.txt")"
  [[ -n "$suite" ]] || vfail "Source ISO exposes no /dists/<suite>/Release; cannot verify repository layout"
  release_path="/dists/$suite/Release"
  grep -Fxq "$release_path" "$tmp_dir/out.txt" \
    || vfail "Remastered ISO lacks required repository file: $release_path"
  grep -Fxq "/.disk/info" "$tmp_dir/out.txt" \
    || vfail "Remastered ISO lacks required installer marker: /.disk/info"
  grep -q "^/pool/" "$tmp_dir/out.txt" \
    || vfail "Remastered ISO lacks /pool repository payload"

  # 3a. Bootloader configs must be present.
  for cfg in ${BOOTLOADER_FILES[@]+"${BOOTLOADER_FILES[@]}"}; do
    grep -Fxq "/$cfg" "$tmp_dir/out.txt" || vfail "Remastered ISO lacks bootloader config: /$cfg"
  done

  # 3b. Injected Omnixys files must be present and the scripts must stay
  # executable-by-interpreter (they are invoked via sh, so presence plus a
  # clean syntax check is the meaningful contract).
  local inject_file
  for inject_file in preseed.cfg omnixys-installer-info.txt omnixys-early.sh omnixys-partman.sh omnixys-network-late.sh omnixys-identity.templates; do
    grep -Fxq "/$inject_file" "$tmp_dir/out.txt" || vfail "Remastered ISO lacks injected file: /$inject_file"
  done

  extract_dir="$tmp_dir/extract"
  ensure_dir "$extract_dir"
  for script_name in omnixys-early.sh omnixys-partman.sh omnixys-network-late.sh; do
    xorriso -osirrox on -indev "$ISO_OUTPUT_PATH" -extract "/$script_name" "$extract_dir/$script_name" >/dev/null 2>&1 \
      || vfail "Remastered ISO: cannot extract /$script_name for validation"
    if ! sh -n "$extract_dir/$script_name" >/dev/null 2>&1; then
      vfail "Remastered ISO: /$script_name fails shell syntax check"
    fi
  done

  rm -rf "$tmp_dir"
  info "Remaster structure verified: suite=$suite, all source paths preserved, Omnixys files present"
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
  if [[ -f "$GENERATED_DIR/omnixys-partman.sh" ]]; then
    run_cmd cp "$GENERATED_DIR/omnixys-partman.sh" "$ISO_TREE_DIR/omnixys-partman.sh"
    run_cmd chmod 0755 "$ISO_TREE_DIR/omnixys-partman.sh"
  fi
  if [[ -f "$GENERATED_DIR/omnixys-network-late.sh" ]]; then
    run_cmd cp "$GENERATED_DIR/omnixys-network-late.sh" "$ISO_TREE_DIR/omnixys-network-late.sh"
    run_cmd chmod 0755 "$ISO_TREE_DIR/omnixys-network-late.sh"
  fi
  run_cmd cp "$ROOT_DIR/templates/omnixys-identity.templates" "$ISO_TREE_DIR/omnixys-identity.templates"
  if debian_identity_embed_enabled && [[ -f "$ROOT_DIR/identity.env" ]]; then
    step "Embedding runtime identity into ISO (IDENTITY_EMBED=true)"
    run_cmd cp "$ROOT_DIR/identity.env" "$ISO_TREE_DIR/identity.env"
  elif [[ -f "$ROOT_DIR/identity.env" ]]; then
    info "Skipping identity embedding (IDENTITY_EMBED=false); /identity.env stays dynamic at install time"
  fi

  step "Patching boot configuration"
  debian_patch_boot_configs "$ISO_TREE_DIR"

  # Refuse to remaster unless the work tree is provably complete (see
  # debian_verify_work_tree_completeness for the deletion-vector rationale).
  step "Verifying work tree completeness against source ISO"
  debian_verify_work_tree_completeness

  if [[ "$DRY_RUN" != "true" ]]; then
    # xorriso refuses a non-empty -outdev media; always start with a clean
    # output file since the remaster below writes a complete new image.
    run_cmd rm -f "$ISO_OUTPUT_PATH"
  fi

  step "Updating remastered ISO with Omnixys files"
  # Cross-image remaster: xorriso copies the source image into the output
  # file while applying the tree updates. The completeness guard above
  # guarantees the tree mirrors every source path, so this pass can only add
  # or refresh Omnixys files and never drops installer content.
  run_cmd xorriso \
    -indev "$ISO_SOURCE_PATH" \
    -outdev "$ISO_OUTPUT_PATH" \
    -boot_image any replay \
    -update_r "$ISO_TREE_DIR" / \
    -commit \
    -end

  debian_assert_no_identity_in_iso

  step "Verifying remastered ISO structure"
  debian_verify_iso_structure

  cp "$GENERATED_DIR/installer-info.txt" "$metadata_copy"
  cp "$GENERATED_DIR/installer-info.txt" "$ARTIFACTS_DIR/installer-info.txt"

  step "Generating output SHA256"
  sha256sum "$ISO_OUTPUT_PATH" | tee "$ISO_OUTPUT_PATH.sha256" >/dev/null
  cp "$ISO_OUTPUT_PATH.sha256" "$ARTIFACTS_DIR/output.${ARCH}.iso.sha256"
}
