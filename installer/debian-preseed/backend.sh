#!/usr/bin/env bash

source "$BACKEND_DIR/validator.sh"
source "$BACKEND_DIR/renderer.sh"
source "$BACKEND_DIR/builder.sh"
source "$BACKEND_DIR/bootloader.sh"

validate() { debian_validate; }
render() { debian_render; }
build() { debian_build; }
verify() { debian_verify; }
package() { debian_package; }
