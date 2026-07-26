#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$BACKEND_DIR/validator.sh"
# shellcheck disable=SC1091
source "$BACKEND_DIR/renderer.sh"
# shellcheck disable=SC1091
source "$BACKEND_DIR/builder.sh"
# shellcheck disable=SC1091
source "$BACKEND_DIR/bootloader.sh"

validate() { debian_validate; }
render() { debian_render; }
build() { debian_build; }
verify() { debian_verify; }
package() { debian_package; }
