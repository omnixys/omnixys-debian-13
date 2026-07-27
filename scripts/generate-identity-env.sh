#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'EOF'
Usage: bash scripts/generate-identity-env.sh [options]

Options:
  --hostname <value>      Required host name.
  --domain <value>        Optional domain.
  --fullname <value>      Required full name.
  --username <value>      Required username.
  --ssh-public-key <key>  Optional SSH public key for runtime override.
  --password <value>      Use the provided cleartext password.
  --generate-password     Generate a random password and print it once.
  --output <file>         Output file path. Default: ./identity.env
  -h, --help              Show this help.

The generated file contains only hashed password material:
  OMNIXYS_PASSWORD_HASH=<hash>

If --generate-password is used, the cleartext password is printed once to stderr.
EOF
}

require_value() {
  local name="$1"
  local value="$2"
  [[ -n "$value" ]] || {
    echo "Missing required option: $name" >&2
    exit 1
  }
}

generate_password() {
  openssl rand -base64 24 | tr -d '\n'
}

main() {
  local hostname=""
  local domain=""
  local fullname=""
  local username=""
  local ssh_public_key=""
  local password=""
  local output_file="identity.env"
  local auto_password="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --hostname)
        hostname="${2:-}"
        shift 2
        ;;
      --domain)
        domain="${2:-}"
        shift 2
        ;;
      --fullname)
        fullname="${2:-}"
        shift 2
        ;;
      --username)
        username="${2:-}"
        shift 2
        ;;
      --ssh-public-key)
        ssh_public_key="${2:-}"
        shift 2
        ;;
      --password)
        password="${2:-}"
        shift 2
        ;;
      --generate-password)
        auto_password="true"
        shift
        ;;
      --output)
        output_file="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done

  require_value --hostname "$hostname"
  require_value --fullname "$fullname"
  require_value --username "$username"

  if [[ -z "$password" && "$auto_password" == "true" ]]; then
    password="$(generate_password)"
    echo "Generated password (shown once): $password" >&2
  fi

  require_value '--password or --generate-password' "$password"

  local password_hash
  password_hash="$(openssl passwd -6 "$password")"

  cat >"$output_file" <<EOF
OMNIXYS_HOSTNAME=$hostname
OMNIXYS_DOMAIN=$domain
OMNIXYS_FULLNAME=$fullname
OMNIXYS_USERNAME=$username
OMNIXYS_SSH_PUBLIC_KEY=$ssh_public_key
OMNIXYS_PASSWORD_HASH=$password_hash
EOF

  echo "Wrote $output_file"
}

main "$@"