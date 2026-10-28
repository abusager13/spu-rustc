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

cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf --thread-exit \
    -o "$tmp/scalar_thread_exit.elf" examples/scalar_entry.rs

cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
    --entry-args=0x12345678,0x5678 -o "$tmp/add_entry.elf" examples/add_u32.rs

cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
    --runtime-args -o "$tmp/runtime_args.elf" examples/add_u32.rs

cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
    --ppu-thread-args --thread-exit -o "$tmp/ppu_thread_args.elf" examples/add_u32.rs
cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
    --ppu-thread-args --thread-exit -o "$tmp/ppu_thread_args4.elf" examples/sum4_u32.rs

cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
    --runtime-args -o "$tmp/load_u32.elf" examples/load_u32.rs
cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
    --runtime-args -o "$tmp/store_u32.elf" examples/store_u32.rs
printf '\x12\x34\x56\x78\x89\xab\xcd\xef\xfe\xdc\xba\x98\x0b\xad\xf0\x0d' \
    > "$tmp/load_words.bin"

run_case() {
    local name=$1 image=$2 expected=$3
    shift 3
    local capture="$tmp/$name.mailbox" log="$tmp/$name.log"
    if ! (cd "$tmp" && ANERG_MBOX="$capture" timeout "${SPU_EMULATOR_TIMEOUT:-10s}" \
        "$emulator" "$@" "$image") >"$log" 2>&1; then
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

check_local_store_store_pattern() {
    local changed_word=$1 index offset expected actual
    local expected_words=(12345678 89abcdef fedcba98 0badf00d)
    for index in 0 1 2 3; do
        offset=$((4096 + index * 4))
        expected=${expected_words[$index]}
        if [[ "$index" == "$changed_word" ]]; then
            expected=deadbeef
        fi
        actual=$(od -An -j "$offset" -N4 -tx1 "$tmp/ls.b" | tr -d '[:space:]')
        if [[ "$actual" != "$expected" ]]; then
            printf -v address '0x%x' "$((0x1000 + index * 4))"
            echo "local-store-store-word-$changed_word: expected word $index at $address to be $expected, got ${actual:-<empty>}" >&2
            exit 1
        fi
    done
    printf 'local-store-store-word-%s: changed word and neighboring words verified in local store\n' "$changed_word"
}

compile_entry() {
    local function=$1 args=$2
    cargo run --quiet --offline -- --target spu-sony-ps3 --emit=elf \
        --entry-args="$args" -o "$tmp/$function.elf" "$root/examples/$function.rs"
}

run_case scalar-entry "$tmp/scalar_entry.elf" 0000002a
run_case scalar-thread-exit "$tmp/scalar_thread_exit.elf" 0000002a
run_case addition-wide "$tmp/add_entry.elf" 1234acf0
if [[ "${SPU_EMULATOR_HAS_REG_PRESETS:-0}" == "1" ]]; then
    run_case runtime-argument-registers "$tmp/runtime_args.elf" 1234acf0 \
        -r 3=12345678 -r 4=00005678
    run_case ppu-thread-u64-low-words "$tmp/ppu_thread_args.elf" 11111100 \
        -r 3=12345678:9abcdef0:0:0 -r 4=fedcba98:76543210:0:0
    run_case ppu-thread-four-u64-arguments "$tmp/ppu_thread_args4.elf" 0000000f \
        -r 3=01234567:00000001:0:0 \
        -r 4=89abcdef:00000002:0:0 \
        -r 5=fedcba98:00000004:0:0 \
        -r 6=76543210:00000008:0:0
    run_case local-store-load-word-0 "$tmp/load_u32.elf" 12345678 \
        -L "$tmp/load_words.bin@0x1000" -r 3=00001000
    run_case local-store-load-word-1 "$tmp/load_u32.elf" 89abcdef \
        -L "$tmp/load_words.bin@0x1000" -r 3=00001004
    run_case local-store-load-word-2 "$tmp/load_u32.elf" fedcba98 \
        -L "$tmp/load_words.bin@0x1000" -r 3=00001008
    run_case local-store-load-word-3 "$tmp/load_u32.elf" 0badf00d \
        -L "$tmp/load_words.bin@0x1000" -r 3=0000100c
    for word_index in 0 1 2 3; do
        address=$(printf '%08x' "$((0x1000 + word_index * 4))")
        run_case "local-store-store-word-$word_index" "$tmp/store_u32.elf" deadbeef \
            -L "$tmp/load_words.bin@0x1000" -r "3=$address" -r 4=deadbeef
        check_local_store_store_pattern "$word_index"
    done
else
    echo "skipping runtime-argument emulator case: set SPU_EMULATOR_HAS_REG_PRESETS=1 when the emulator supports -r register presets"
fi

stack_args=""
for ((index = 0; index < 72; index++)); do
    stack_args+="0,"
done
compile_entry stack_arg_u32 "${stack_args}42"
run_case stack-passed-argument "$tmp/stack_arg_u32.elf" 0000002a
compile_entry stack_arg_u32 "${stack_args}0x12345678"
run_case stack-passed-full-width-argument "$tmp/stack_arg_u32.elf" 12345678
compile_entry stack_args_u32 "${stack_args}1,2,4"
run_case three-stack-passed-arguments "$tmp/stack_args_u32.elf" 00000007

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
compile_entry not_u32 0
run_case bitwise-not-zero "$tmp/not_u32.elf" ffffffff
compile_entry not_u32 0x12345678
run_case bitwise-not-pattern "$tmp/not_u32.elf" edcba987

compile_entry wrapping_neg_u32 0
run_case wrapping-neg-zero "$tmp/wrapping_neg_u32.elf" 00000000
compile_entry wrapping_neg_u32 1
run_case wrapping-neg-one "$tmp/wrapping_neg_u32.elf" ffffffff
compile_entry wrapping_neg_u32 0x80000000
run_case wrapping-neg-high-bit "$tmp/wrapping_neg_u32.elf" 80000000
compile_entry wrapping_neg_u32 0x12345678
run_case wrapping-neg-pattern "$tmp/wrapping_neg_u32.elf" edcba988
compile_entry wrapping_neg_i32 0xffffffff
run_case signed-wrapping-neg-negative-one "$tmp/wrapping_neg_i32.elf" 00000001
compile_entry wrapping_neg_i32 0x80000000
run_case signed-wrapping-neg-minimum "$tmp/wrapping_neg_i32.elf" 80000000

compile_entry wrapping_shl_u32 1,32
run_case wrapping-left-shift "$tmp/wrapping_shl_u32.elf" 00000001
compile_entry wrapping_shr_u32 0x80000001,33
run_case wrapping-logical-right-shift "$tmp/wrapping_shr_u32.elf" 40000000
compile_entry wrapping_shr_i32 0x80000000,1
run_case wrapping-arithmetic-right-shift "$tmp/wrapping_shr_i32.elf" c0000000

compile_entry rotate_left_u32 0x80000001,0
run_case rotate-left-count-0 "$tmp/rotate_left_u32.elf" 80000001
compile_entry rotate_left_u32 0x80000001,1
run_case rotate-left-count-1 "$tmp/rotate_left_u32.elf" 00000003
compile_entry rotate_left_u32 0x80000001,31
run_case rotate-left-count-31 "$tmp/rotate_left_u32.elf" c0000000
compile_entry rotate_left_u32 0x80000001,32
run_case rotate-left-count-32 "$tmp/rotate_left_u32.elf" 80000001
compile_entry rotate_left_u32 0x80000001,33
run_case rotate-left-count-33 "$tmp/rotate_left_u32.elf" 00000003
compile_entry rotate_left_u32 0x80000001,0xffffffff
run_case rotate-left-high-count "$tmp/rotate_left_u32.elf" c0000000

compile_entry rotate_right_u32 0x80000001,0
run_case rotate-right-count-0 "$tmp/rotate_right_u32.elf" 80000001
compile_entry rotate_right_u32 0x80000001,1
run_case rotate-right-count-1 "$tmp/rotate_right_u32.elf" c0000000
compile_entry rotate_right_u32 0x80000001,31
run_case rotate-right-count-31 "$tmp/rotate_right_u32.elf" 00000003
compile_entry rotate_right_u32 0x80000001,32
run_case rotate-right-count-32 "$tmp/rotate_right_u32.elf" 80000001
compile_entry rotate_right_u32 0x80000001,33
run_case rotate-right-count-33 "$tmp/rotate_right_u32.elf" c0000000
compile_entry rotate_right_u32 0x80000001,0xffffffff
run_case rotate-right-high-count "$tmp/rotate_right_u32.elf" 00000003

compile_entry rotate_left_const_u32 0x80000001
run_case rotate-left-constant "$tmp/rotate_left_const_u32.elf" 00000030
compile_entry rotate_right_const_u32 0x80000001
run_case rotate-right-constant "$tmp/rotate_right_const_u32.elf" 0c000000

compile_entry leading_zeros_u32 0
run_case leading-zeros-zero "$tmp/leading_zeros_u32.elf" 00000020
compile_entry leading_zeros_u32 1
run_case leading-zeros-one "$tmp/leading_zeros_u32.elf" 0000001f
compile_entry leading_zeros_u32 0x80000000
run_case leading-zeros-top-bit "$tmp/leading_zeros_u32.elf" 00000000
compile_entry leading_zeros_u32 0x00100000
run_case leading-zeros-interior-bit "$tmp/leading_zeros_u32.elf" 0000000b
compile_entry leading_zeros_u32 0xffffffff
run_case leading-zeros-all-ones "$tmp/leading_zeros_u32.elf" 00000000

compile_entry trailing_zeros_u32 0
run_case trailing-zeros-zero "$tmp/trailing_zeros_u32.elf" 00000020
compile_entry trailing_zeros_u32 1
run_case trailing-zeros-one "$tmp/trailing_zeros_u32.elf" 00000000
compile_entry trailing_zeros_u32 8
run_case trailing-zeros-eight "$tmp/trailing_zeros_u32.elf" 00000003
compile_entry trailing_zeros_u32 0x80000000
run_case trailing-zeros-top-bit "$tmp/trailing_zeros_u32.elf" 0000001f
compile_entry trailing_zeros_u32 0xf0f00000
run_case trailing-zeros-interior-bit "$tmp/trailing_zeros_u32.elf" 00000014
compile_entry trailing_zeros_u32 0xffffffff
run_case trailing-zeros-all-ones "$tmp/trailing_zeros_u32.elf" 00000000

compile_entry leading_ones_u32 0
run_case leading-ones-zero "$tmp/leading_ones_u32.elf" 00000000
compile_entry leading_ones_u32 0x80000000
run_case leading-ones-top-bit "$tmp/leading_ones_u32.elf" 00000001
compile_entry leading_ones_u32 0xf0f00000
run_case leading-ones-interior-pattern "$tmp/leading_ones_u32.elf" 00000004
compile_entry leading_ones_u32 0xffffffff
run_case leading-ones-all-ones "$tmp/leading_ones_u32.elf" 00000020

compile_entry trailing_ones_u32 0
run_case trailing-ones-zero "$tmp/trailing_ones_u32.elf" 00000000
compile_entry trailing_ones_u32 1
run_case trailing-ones-one "$tmp/trailing_ones_u32.elf" 00000001
compile_entry trailing_ones_u32 3
run_case trailing-ones-low-run "$tmp/trailing_ones_u32.elf" 00000002
compile_entry trailing_ones_u32 0x80000000
run_case trailing-ones-top-bit-only "$tmp/trailing_ones_u32.elf" 00000000
compile_entry trailing_ones_u32 0xffffffff
run_case trailing-ones-all-ones "$tmp/trailing_ones_u32.elf" 00000020

compile_entry wrapping_abs_i32 0
run_case wrapping-abs-zero "$tmp/wrapping_abs_i32.elf" 00000000
compile_entry wrapping_abs_i32 5
run_case wrapping-abs-positive "$tmp/wrapping_abs_i32.elf" 00000005
compile_entry wrapping_abs_i32 0xfffffffb
run_case wrapping-abs-negative "$tmp/wrapping_abs_i32.elf" 00000005
compile_entry wrapping_abs_i32 0x80000000
run_case wrapping-abs-i32-min "$tmp/wrapping_abs_i32.elf" 80000000
compile_entry wrapping_abs_i32 0x7fffffff
run_case wrapping-abs-i32-max "$tmp/wrapping_abs_i32.elf" 7fffffff

compile_entry reverse_bits_u32 0
run_case reverse-bits-zero "$tmp/reverse_bits_u32.elf" 00000000
compile_entry reverse_bits_u32 1
run_case reverse-bits-low-bit "$tmp/reverse_bits_u32.elf" 80000000
compile_entry reverse_bits_u32 0x80000000
run_case reverse-bits-high-bit "$tmp/reverse_bits_u32.elf" 00000001
compile_entry reverse_bits_u32 0x01234567
run_case reverse-bits-mixed-pattern "$tmp/reverse_bits_u32.elf" e6a2c480
compile_entry reverse_bits_u32 0xffffffff
run_case reverse-bits-all-ones "$tmp/reverse_bits_u32.elf" ffffffff

compile_entry swap_bytes_u32 0
run_case swap-bytes-zero "$tmp/swap_bytes_u32.elf" 00000000
compile_entry swap_bytes_u32 1
run_case swap-bytes-low-byte "$tmp/swap_bytes_u32.elf" 01000000
compile_entry swap_bytes_u32 0x12345678
run_case swap-bytes-mixed-pattern "$tmp/swap_bytes_u32.elf" 78563412
compile_entry swap_bytes_u32 0xffffffff
run_case swap-bytes-all-ones "$tmp/swap_bytes_u32.elf" ffffffff

compile_entry min_i32 0x80000000,0x7fffffff
run_case signed-min-crosses-zero "$tmp/min_i32.elf" 80000000
compile_entry min_i32 0xffffffff,0x80000000
run_case signed-min-negative-order "$tmp/min_i32.elf" 80000000
compile_entry max_i32 0x80000000,0x7fffffff
run_case signed-max-crosses-zero "$tmp/max_i32.elf" 7fffffff
compile_entry max_i32 0xffffffff,0x80000000
run_case signed-max-negative-order "$tmp/max_i32.elf" ffffffff
compile_entry max_i32 7,7
run_case signed-max-equal "$tmp/max_i32.elf" 00000007

compile_entry min_u32 0x80000000,0x7fffffff
run_case unsigned-min-crosses-sign-bit "$tmp/min_u32.elf" 7fffffff
compile_entry min_u32 0xffffffff,0x80000000
run_case unsigned-min-high-values "$tmp/min_u32.elf" 80000000
compile_entry max_u32 0x80000000,0x7fffffff
run_case unsigned-max-crosses-sign-bit "$tmp/max_u32.elf" 80000000
compile_entry max_u32 0xffffffff,0x80000000
run_case unsigned-max-high-values "$tmp/max_u32.elf" ffffffff
compile_entry max_u32 9,9
run_case unsigned-max-equal "$tmp/max_u32.elf" 00000009

compile_entry saturating_add_u32 0xfffffff0,0x30
run_case saturating-add-overflow "$tmp/saturating_add_u32.elf" ffffffff
compile_entry saturating_add_u32 0xfffffffe,1
run_case saturating-add-to-max "$tmp/saturating_add_u32.elf" ffffffff
compile_entry saturating_add_u32 0x12345678,0x100
run_case saturating-add-no-overflow "$tmp/saturating_add_u32.elf" 12345778
compile_entry saturating_add_u32 0x80000000,0x80000000
run_case saturating-add-two-high-values "$tmp/saturating_add_u32.elf" ffffffff

compile_entry saturating_sub_u32 0,1
run_case saturating-sub-zero-underflow "$tmp/saturating_sub_u32.elf" 00000000
compile_entry saturating_sub_u32 7,7
run_case saturating-sub-exact-zero "$tmp/saturating_sub_u32.elf" 00000000
compile_entry saturating_sub_u32 0xffffffff,1
run_case saturating-sub-no-underflow "$tmp/saturating_sub_u32.elf" fffffffe
compile_entry saturating_sub_u32 0x80000000,0x7fffffff
run_case saturating-sub-crosses-sign-bit "$tmp/saturating_sub_u32.elf" 00000001

compile_entry saturating_add_i32 0x7fffffff,1
run_case saturating-add-i32-positive-overflow "$tmp/saturating_add_i32.elf" 7fffffff
compile_entry saturating_add_i32 0x80000000,0xffffffff
run_case saturating-add-i32-negative-overflow "$tmp/saturating_add_i32.elf" 80000000
compile_entry saturating_add_i32 10,0xfffffffc
run_case saturating-add-i32-no-overflow "$tmp/saturating_add_i32.elf" 00000006
compile_entry saturating_add_i32 0x7fffffff,0xffffffff
run_case saturating-add-i32-boundary-no-overflow "$tmp/saturating_add_i32.elf" 7ffffffe

compile_entry saturating_sub_i32 0x7fffffff,0xffffffff
run_case saturating-sub-i32-positive-overflow "$tmp/saturating_sub_i32.elf" 7fffffff
compile_entry saturating_sub_i32 0x80000000,1
run_case saturating-sub-i32-negative-overflow "$tmp/saturating_sub_i32.elf" 80000000
compile_entry saturating_sub_i32 0xfffffffb,7
run_case saturating-sub-i32-no-overflow "$tmp/saturating_sub_i32.elf" fffffff4
compile_entry saturating_sub_i32 0x80000000,0xffffffff
run_case saturating-sub-i32-boundary-no-overflow "$tmp/saturating_sub_i32.elf" 80000001

compile_entry select_i32 10,20
run_case select-signed-true-arm  "$tmp/select_i32.elf" 0000000a
compile_entry select_i32 0x80000000,20
run_case select-signed-false-arm "$tmp/select_i32.elf" 00000014
compile_entry select_computed_i32 10,20
run_case select-computed-true-arm "$tmp/select_computed_i32.elf" 0000001b
compile_entry select_computed_i32 0xfffffff6,0x12345678
run_case select-computed-false-arm "$tmp/select_computed_i32.elf" edcba98e

if [[ "${SPU_EMULATOR_HAS_SUMB:-0}" == "1" ]]; then
    compile_entry count_ones_u32 0
    run_case count-ones-zero "$tmp/count_ones_u32.elf" 00000000
    compile_entry count_ones_u32 1
    run_case count-ones-one "$tmp/count_ones_u32.elf" 00000001
    compile_entry count_ones_u32 0x80000000
    run_case count-ones-top-bit "$tmp/count_ones_u32.elf" 00000001
    compile_entry count_ones_u32 0xf0f00f0f
    run_case count-ones-alternating-bytes "$tmp/count_ones_u32.elf" 00000010
    compile_entry count_ones_u32 0xffffffff
    run_case count-ones-all-ones "$tmp/count_ones_u32.elf" 00000020
else
    echo "skipping count-ones emulator cases: set SPU_EMULATOR_HAS_SUMB=1 when the emulator implements sumb"
fi

compile_entry cmp_eq_u32 0xffffffff,0xffffffff
run_case comparison-equal "$tmp/cmp_eq_u32.elf" 00000001
compile_entry cmp_ne_u32 7,7
run_case comparison-not-equal-false "$tmp/cmp_ne_u32.elf" 00000000
compile_entry cmp_sgt_i32 0x7fffffff,0xffffffff
run_case comparison-signed-greater "$tmp/cmp_sgt_i32.elf" 00000001
compile_entry cmp_ugt_u32 0xffffffff,0x7fffffff
run_case comparison-unsigned-greater "$tmp/cmp_ugt_u32.elf" 00000001
