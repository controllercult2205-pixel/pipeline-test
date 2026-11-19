#!/usr/bin/env bash
# Encrypts or decrypts the sensitive plan files (tfplan, plan.json) in the
# current directory with symmetric GPG (AES256).
#   encrypt: writes <file>.gpg and deletes the plaintext
#   decrypt: restores <file> from <file>.gpg
# The passphrase is passed on stdin, never on the command line.
#
# Usage : plan-crypt.sh encrypt|decrypt
# Env in: PASSPHRASE
set -euo pipefail

mode="${1:-}"
files=(tfplan plan.json)

if [ -z "${PASSPHRASE:-}" ]; then
  echo "::error::PASSPHRASE is required."
  exit 1
fi

gpg_run() {
  printf '%s' "$PASSPHRASE" | gpg --batch --yes --no-symkey-cache \
    --pinentry-mode loopback --passphrase-fd 0 "$@"
}

case "$mode" in
  encrypt)
    for f in "${files[@]}"; do
      gpg_run --symmetric --cipher-algo AES256 -o "$f.gpg" "$f"
    done
    rm -f "${files[@]}"
    ;;
  decrypt)
    for f in "${files[@]}"; do
      gpg_run --decrypt -o "$f" "$f.gpg"
    done
    ;;
  *)
    echo "usage: $0 encrypt|decrypt" >&2
    exit 2
    ;;
esac
