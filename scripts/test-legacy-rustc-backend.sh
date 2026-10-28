#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
toolchain=${RUSTC_TOOLCHAIN:-nightly-2021-12-30}
backend=${CODEGEN_BACKEND:-}
spu_as=${SPU_AS:-spu-as}
spu_ld=${SPU_LD:-spu-ld}
spu_readelf=${SPU_READELF:-spu-readelf}
emulator=${SPU_EMULATOR:-anergistic}

if [[ -z "$backend" || ! -f "$backend" ]]; then
    echo "Set CODEGEN_BACKEND to the legacy rustc_codegen_gcc shared library" >&2
    exit 2
fi
if [[ -z "${LD_PRELOAD:-}" || -z "${LD_LIBRARY_PATH:-}" ]]; then
    echo "Set LD_PRELOAD to the temporary GCC 9.5 compatibility shim and LD_LIBRARY_PATH to the GCC 9.5 SPU libgccjit dependencies" >&2
    exit 2
fi

if [[ -n "${RUSTC:-}" ]]; then
    rustc_command=("$RUSTC")
    rustc_prefix=()
else
    rustc_command=(rustc)
    rustc_prefix=("+$toolchain")
fi

for tool in "$spu_as" "$spu_ld" "$spu_readelf" "$emulator" timeout; do
    command -v -- "$tool" >/dev/null || {
        echo "Required tool not found: $tool" >&2
        exit 127
    }
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/spu-legacy-rustc.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

cfg=$("${rustc_command[@]}" "${rustc_prefix[@]}" -Z unstable-options \
    --print cfg --target="$root/experiments/legacy-rustc/target.json")
for expected in 'target_arch="spu"' 'target_endian="big"' 'target_pointer_width="32"'; do
    if ! grep -Fxq "$expected" <<<"$cfg"; then
        echo "Unexpected custom target cfg; expected $expected" >&2
        exit 1
    fi
done

"${rustc_command[@]}" "${rustc_prefix[@]}" -Z unstable-options \
    -Zcodegen-backend="$backend" \
    --target="$root/experiments/legacy-rustc/target.json" \
    --crate-type=lib --emit=obj -Cpanic=abort -Copt-level=1 \
    -o "$tmp/identity.o" "$root/experiments/legacy-rustc/identity.rs"

header=$("$spu_readelf" -h "$tmp/identity.o")
for expected in "Class:                             ELF32" \
    "Data:                              2's complement, big endian" \
    "Machine:                           SPU"; do
    if ! grep -Fq "$expected" <<<"$header"; then
        echo "Unexpected Rust object header; expected $expected" >&2
        exit 1
    fi
done

"$spu_as" -o "$tmp/start.o" "$root/experiments/legacy-rustc/start.s"
"$spu_ld" -Ttext=0 -e _start -o "$tmp/identity.elf" \
    "$tmp/start.o" "$tmp/identity.o"

header=$("$spu_readelf" -h "$tmp/identity.elf")
for expected in "Class:                             ELF32" \
    "Data:                              2's complement, big endian" \
    "Type:                              EXEC (Executable file)" \
    "Machine:                           SPU"; do
    if ! grep -Fq "$expected" <<<"$header"; then
        echo "Unexpected Rust executable header; expected $expected" >&2
        exit 1
    fi
done

if ! (cd "$tmp" && ANERG_MBOX="$tmp/mailbox" timeout "${SPU_EMULATOR_TIMEOUT:-10s}" \
    "$emulator" "$tmp/identity.elf") >"$tmp/emulator.log" 2>&1; then
    cat "$tmp/emulator.log" >&2
    echo "Legacy Rust SPU emulator run failed or timed out" >&2
    exit 1
fi
if ! grep -Fq '####### stop instruction reached:' "$tmp/emulator.log"; then
    cat "$tmp/emulator.log" >&2
    echo "Legacy Rust SPU image did not reach stop" >&2
    exit 1
fi

actual=$(od -An -N4 -tx1 "$tmp/mailbox" | tr -d '[:space:]')
if [[ "$actual" != 0000002a ]]; then
    echo "Expected identity result 0000002a, got ${actual:-<empty>}" >&2
    exit 1
fi
echo "legacy rustc Rust-ABI identity: ELF32 EM_SPU; emulator returned 42 and reached stop"
