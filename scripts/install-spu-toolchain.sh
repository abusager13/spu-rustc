#!/usr/bin/env bash
set -euo pipefail

destination="${1:-${HOME}/opt}"
archive="$(mktemp)"
trap 'rm -f "$archive"' EXIT

release_url="https://github.com/ps3dev/ps3toolchain/releases/download/nightly-2026-10-11/ps3dev-linux-X64.tar.gz"
expected_sha256="66afbfc725221d3a6f02f219a6ce47ee793ff6b0890f176a9d10d2c89c91dda5"

curl --fail --location --silent --show-error "$release_url" --output "$archive"
if ! printf '%s  %s\n' "$expected_sha256" "$archive" | sha256sum --check --status; then
    echo "SPU toolchain archive SHA-256 did not match the pinned release" >&2
    exit 1
fi

mkdir -p "$destination"
tar -xzf "$archive" -C "$destination" ps3dev/spu
