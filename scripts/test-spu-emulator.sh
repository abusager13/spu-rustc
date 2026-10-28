#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
emulator=${SPU_EMULATOR:-${1:-anergistic}}
spu_as=${SPU_AS:-spu-as}
spu_ld=${SPU_LD:-spu-ld}

resolve_executable() {
    local name=$1
    if [[ "$name" == */* ]]; then
        local dir base
        dir=$(cd -- "$(dirname -- "$name")" && pwd)
        base=$(basename -- "$name")
        printf '%s/%s\n' "$dir" "$base"
    else
        command -v -- "$name"
    fi
}

emulator=$(resolve_executable "$emulator") || {
    echo "SPU emulator not found; pass its path or set SPU_EMULATOR" >&2
    exit 127
}
command -v -- "$spu_as" >/dev/null || {
    echo "SPU assembler not found; set SPU_AS" >&2
    exit 127
}
command -v -- "$spu_ld" >/dev/null || {
    echo "SPU linker not found; set SPU_LD" >&2
    exit 127
}
command -v cargo >/dev/null || {
    echo "cargo not found" >&2
    exit 127
}
command -v timeout >/dev/null || {
    echo "GNU timeout is required to bound emulator runs" >&2
    exit 127
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/spu-rust-emulator.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
cd "$root"

cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
    -o "$tmp/scalar_entry.elf" examples/scalar_entry.rs

cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
    --entry-args=0x12345678,0x5678 -o "$tmp/add_entry.elf" examples/add_u32.rs

run_case() {
    local name=$1 image=$2 expected=$3
    local capture="$tmp/$name.mailbox" log="$tmp/$name.log"
    if ! (cd "$tmp" && ANERG_MBOX="$capture" timeout "${SPU_EMULATOR_TIMEOUT:-10s}" \
        "$emulator" "$image") >"$log" 2>&1; then
        cat "$log" >&2
        echo "$name: emulator failed or timed out" >&2
        return 1
    fi
    if ! grep -Fq '####### stop instruction reached:' "$log"; then
        cat "$log" >&2
        echo "$name: emulator did not reach SPU stop" >&2
        return 1
    fi
    local actual byte_count
    byte_count=$(wc -c < "$capture")
    if [[ "$byte_count" != 4 ]]; then
        cat "$log" >&2
        echo "$name: expected one 4-byte mailbox result, got $byte_count bytes" >&2
        return 1
    fi
    actual=$(od -An -N4 -tx1 "$capture" | tr -d '[:space:]')
    if [[ "$actual" != "$expected" ]]; then
        cat "$log" >&2
        echo "$name: expected mailbox $expected, got ${actual:-<empty>}" >&2
        return 1
    fi
    printf '%s: stop reached; outbound mailbox = 0x%s\n' "$name" "$actual"
    grep -E '^ pc:|^003:' "$log" || true
}

compile_entry() {
    local function=$1 args=$2
    cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
        --entry-args="$args" -o "$tmp/$function.elf" "$root/examples/$function.rs"
}

run_case scalar-entry "$tmp/scalar_entry.elf" 0000002a
run_case addition-wide "$tmp/add_entry.elf" 1234acf0

compile_entry sub_u32 100,7
run_case subtraction "$tmp/sub_u32.elf" 0000005d
compile_entry mul_u32 0xffffffff,0xffffffff
run_case multiplication-overflow "$tmp/mul_u32.elf" 00000001
compile_entry mul_u32 0x12345678,0x9abcdef0
run_case multiplication-cross-products "$tmp/mul_u32.elf" 242d2080
compile_entry mul_i32 0xfffffffe,7
run_case signed-multiplication-wrapping "$tmp/mul_i32.elf" fffffff2
compile_entry mul_constant_u32 0x89abcdef
run_case multiplication-constant "$tmp/mul_constant_u32.elf" e242d208
compile_entry and_u32 0xf0f0,0x0ff0
run_case bitwise-and "$tmp/and_u32.elf" 000000f0
compile_entry or_u32 0xf000,0x00f0
run_case bitwise-or "$tmp/or_u32.elf" 0000f0f0
compile_entry xor_u32 0xffff0000,0x0000ffff
run_case bitwise-xor "$tmp/xor_u32.elf" ffffffff

compile_entry wrapping_shl_u32 1,32
run_case wrapping-left-shift "$tmp/wrapping_shl_u32.elf" 00000001
compile_entry wrapping_shr_u32 0x80000001,33
run_case wrapping-logical-right-shift "$tmp/wrapping_shr_u32.elf" 40000000
compile_entry wrapping_shr_i32 0x80000000,1
run_case wrapping-arithmetic-right-shift "$tmp/wrapping_shr_i32.elf" c0000000

compile_entry cmp_eq_u32 0xffffffff,0xffffffff
run_case comparison-equal "$tmp/cmp_eq_u32.elf" 00000001
compile_entry cmp_ne_u32 7,7
run_case comparison-not-equal-false "$tmp/cmp_ne_u32.elf" 00000000
compile_entry cmp_sgt_i32 0x7fffffff,0xffffffff
run_case comparison-signed-greater "$tmp/cmp_sgt_i32.elf" 00000001
compile_entry cmp_ugt_u32 0xffffffff,0x7fffffff
run_case comparison-unsigned-greater "$tmp/cmp_ugt_u32.elf" 00000001
