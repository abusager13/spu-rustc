#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"

rustc=${RUSTC:-rustc}
llc=${LLC:-llc}
spu_as=${SPU_AS:-spu-as}
spu_ld=${SPU_LD:-spu-ld}
spu_cc=${SPU_CC:-spu-gcc}
spu_readelf=${SPU_READELF:-spu-readelf}
spu_objdump=${SPU_OBJDUMP:-spu-objdump}
emulator=${SPU_EMULATOR:-anergistic}

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

rustc=$(resolve_executable "$rustc") || {
    echo "Rust compiler not found; set RUSTC" >&2
    exit 127
}
llc=$(resolve_executable "$llc") || {
    echo "LLVM llc not found; set LLC to the LLVM 23.1.1 build" >&2
    exit 127
}
spu_as=$(resolve_executable "$spu_as") || {
    echo "SPU assembler not found; set SPU_AS" >&2
    exit 127
}
spu_ld=$(resolve_executable "$spu_ld") || {
    echo "SPU linker not found; set SPU_LD" >&2
    exit 127
}
spu_cc=$(resolve_executable "$spu_cc") || {
    echo "SPU GCC compiler not found; set SPU_CC" >&2
    exit 127
}
spu_readelf=$(resolve_executable "$spu_readelf") || {
    echo "SPU readelf not found; set SPU_READELF" >&2
    exit 127
}
spu_objdump=$(resolve_executable "$spu_objdump") || {
    echo "SPU objdump not found; set SPU_OBJDUMP" >&2
    exit 127
}
emulator=$(resolve_executable "$emulator") || {
    echo "SPU emulator not found; set SPU_EMULATOR" >&2
    exit 127
}
command -v timeout >/dev/null || {
    echo "GNU timeout is required to bound emulator runs" >&2
    exit 127
}

rustc_version=$("$rustc" --version)
if [[ "$rustc_version" != *"rustc 1.99.1 "* ]]; then
    echo "expected the project-pinned Rust 1.99.1 compiler, found: $rustc_version" >&2
    exit 2
fi

version=$("$llc" --version)
if [[ "$version" != *"LLVM version 23.1.1"* || \
      "$version" != *"cellspu - STI CBEA Cell SPU"* ]]; then
    echo "LLC must be LLVM 23.1.1 with the CellSPU target registered" >&2
    exit 2
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/llvm-cellspu-smoke.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

cat >"$tmp/scalar.rs" <<'RUST'
#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn add_u32(lhs: u32, rhs: u32) -> u32 {
    lhs.wrapping_add(rhs)
}

#[unsafe(no_mangle)]
pub extern "C" fn sub_u32(lhs: u32, rhs: u32) -> u32 {
    lhs.wrapping_sub(rhs)
}

#[unsafe(no_mangle)]
pub extern "C" fn and_u32(lhs: u32, rhs: u32) -> u32 {
    lhs & rhs
}

#[unsafe(no_mangle)]
pub extern "C" fn or_u32(lhs: u32, rhs: u32) -> u32 {
    lhs | rhs
}

#[unsafe(no_mangle)]
pub extern "C" fn xor_u32(lhs: u32, rhs: u32) -> u32 {
    lhs ^ rhs
}

#[unsafe(no_mangle)]
pub extern "C" fn increment_u32(value: u32) -> u32 {
    value.wrapping_add(1)
}

#[unsafe(no_mangle)]
pub extern "C" fn constant_u32() -> u32 {
    42
}

#[unsafe(no_mangle)]
pub extern "C" fn eq_u32(lhs: u32, rhs: u32) -> u32 {
    u32::from(lhs == rhs)
}

#[unsafe(no_mangle)]
pub extern "C" fn max_u32(lhs: u32, rhs: u32) -> u32 {
    if lhs > rhs { lhs } else { rhs }
}

#[unsafe(no_mangle)]
pub extern "C" fn max_i32(lhs: i32, rhs: i32) -> i32 {
    if lhs > rhs { lhs } else { rhs }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_eq(lhs: u32, rhs: u32) -> u32 {
    if lhs == rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ne(lhs: u32, rhs: u32) -> u32 {
    if lhs != rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_slt(lhs: i32, rhs: i32) -> u32 {
    if lhs < rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_sle(lhs: i32, rhs: i32) -> u32 {
    if lhs <= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_sge(lhs: i32, rhs: i32) -> u32 {
    if lhs >= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ult(lhs: u32, rhs: u32) -> u32 {
    if lhs < rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ule(lhs: u32, rhs: u32) -> u32 {
    if lhs <= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_uge(lhs: u32, rhs: u32) -> u32 {
    if lhs >= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_eq_i16(lhs: i16, rhs: i16) -> u32 {
    if lhs == rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ne_i16(lhs: i16, rhs: i16) -> u32 {
    if lhs != rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_slt_i16(lhs: i16, rhs: i16) -> u32 {
    if lhs < rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_sle_i16(lhs: i16, rhs: i16) -> u32 {
    if lhs <= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_sge_i16(lhs: i16, rhs: i16) -> u32 {
    if lhs >= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ult_u16(lhs: u16, rhs: u16) -> u32 {
    if lhs < rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ule_u16(lhs: u16, rhs: u16) -> u32 {
    if lhs <= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_uge_u16(lhs: u16, rhs: u16) -> u32 {
    if lhs >= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn load_word(pointer: *const u32) -> u32 {
    unsafe { *pointer }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn store_word(pointer: *mut u32, value: u32) {
    unsafe { *pointer = value; }
}

#[unsafe(no_mangle)]
pub extern "C" fn max_i16(lhs: i16, rhs: i16) -> i16 {
    if lhs > rhs { lhs } else { rhs }
}

#[unsafe(no_mangle)]
pub extern "C" fn max_u16(lhs: u16, rhs: u16) -> u16 {
    if lhs > rhs { lhs } else { rhs }
}

#[unsafe(no_mangle)]
pub extern "C" fn sum_to_n(n: u32) -> u32 {
    let mut i = 0u32;
    let mut total = 0u32;
    while i < n {
        total = total.wrapping_add(i);
        i = i.wrapping_add(1);
    }
    total
}

#[unsafe(no_mangle)]
pub extern "C" fn shift_left_const(value: u32) -> u32 {
    value << 3
}

#[unsafe(no_mangle)]
pub extern "C" fn shift_right_const(value: u32) -> u32 {
    value >> 5
}

#[unsafe(no_mangle)]
pub extern "C" fn shift_arithmetic_const(value: i32) -> i32 {
    value >> 4
}
RUST

cat >"$tmp/dynamic_shift.rs" <<'RUST'
#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn shift_left_dynamic(value: u32, count: u32) -> u32 {
    value << (count & 31)
}

#[unsafe(no_mangle)]
pub extern "C" fn shift_right_dynamic(value: u32, count: u32) -> u32 {
    value >> (count & 31)
}

#[unsafe(no_mangle)]
pub extern "C" fn shift_arithmetic_dynamic(value: i32, count: u32) -> i32 {
    value >> (count & 31)
}

#[unsafe(no_mangle)]
pub extern "C" fn wrapping_mul(lhs: u32, rhs: u32) -> u32 {
    lhs.wrapping_mul(rhs)
}

#[unsafe(no_mangle)]
pub extern "C" fn leading_zero_count(value: u32) -> u32 {
    value.leading_zeros()
}

#[unsafe(no_mangle)]
pub extern "C" fn trailing_zero_count(value: u32) -> u32 {
    value.trailing_zeros()
}

#[unsafe(no_mangle)]
pub extern "C" fn population_count(value: u32) -> u32 {
    value.count_ones()
}

#[unsafe(no_mangle)]
pub extern "C" fn leading_one_count(value: u32) -> u32 {
    value.leading_ones()
}

#[unsafe(no_mangle)]
pub extern "C" fn trailing_one_count(value: u32) -> u32 {
    value.trailing_ones()
}

#[unsafe(no_mangle)]
pub extern "C" fn rotate_left(value: u32, count: u32) -> u32 {
    value.rotate_left(count)
}

#[unsafe(no_mangle)]
pub extern "C" fn rotate_right(value: u32, count: u32) -> u32 {
    value.rotate_right(count)
}

#[unsafe(no_mangle)]
pub extern "C" fn swap_bytes(value: u32) -> u32 {
    value.swap_bytes()
}
RUST

"$rustc" --crate-type=lib --emit=llvm-ir -C panic=abort -C opt-level=1 \
    -o "$tmp/dynamic_shift.ll" "$tmp/dynamic_shift.rs"

# rustc emits host LLVM IR here. Replace its host data layout and triple with
# the CellSPU values before code generation; this remains a bootstrap path, not
# a supported rustc SPU target.
"$rustc" --crate-type=lib --emit=llvm-ir -C panic=abort -C opt-level=0 \
    -o "$tmp/scalar.ll" "$tmp/scalar.rs"
cat >"$tmp/optimized_loop.rs" <<'RUST'
#![no_std]

#[inline(never)]
pub extern "C" fn opaque_step(value: u32) -> u32 {
    value.wrapping_add(3)
}

#[unsafe(no_mangle)]
pub extern "C" fn sum_steps_opt(n: u32) -> u32 {
    let mut i = 0u32;
    let mut total = 0u32;
    while i < n {
        total = total.wrapping_add(opaque_step(i));
        i = i.wrapping_add(1);
    }
    total
}
RUST
"$rustc" --crate-type=lib --emit=llvm-ir -C panic=abort -C opt-level=1 \
    -o "$tmp/optimized_loop.ll" "$tmp/optimized_loop.rs"

python3 - "$tmp/stack_args.rs" <<'PY'
from pathlib import Path
import sys

params = ", ".join(f"a{i}: u32" for i in range(73))
args = ", ".join(f"a{i}" for i in range(73))
constant_args = ", ".join(["0u32"] * 72 + ["0x12345678u32"])
Path(sys.argv[1]).write_text(
    "#![no_std]\n#![allow(unused_variables)]\n"
    "#[inline(never)]\n#[unsafe(no_mangle)]\n"
    f'pub extern "C" fn rust_last_arg({params}) -> u32 {{ a72 }}\n'
    "#[inline(never)]\n#[unsafe(no_mangle)]\n"
    f'pub extern "C" fn rust_forward_last_arg({params}) -> u32 {{\n'
    f"    rust_last_arg({args})\n}}\n"
    "#[inline(never)]\n#[unsafe(no_mangle)]\n"
    "pub extern \"C\" fn rust_call_last_arg() -> u32 {\n"
    f"    rust_last_arg({constant_args})\n}}\n"
)
PY
"$rustc" --crate-type=lib --emit=llvm-ir -C panic=abort -C opt-level=0 \
    -o "$tmp/stack_args.ll" "$tmp/stack_args.rs"

python3 - "$tmp/scalar.ll" "$tmp/scalar-spu.ll" \
    "$tmp/optimized_loop.ll" "$tmp/optimized_loop-spu.ll" \
    "$tmp/stack_args.ll" "$tmp/stack_args-spu.ll" \
    "$tmp/dynamic_shift.ll" "$tmp/dynamic_shift-spu.ll" <<'PY'
import pathlib
import re
import sys

data_layout = (
    "E-p:32:32:128-f64:64:128-f32:32:128-i64:32:128-i32:32:128"
    "-i16:16:128-i8:8:128-i1:8:128-a:0:128-v64:64:128-v128:128:128"
    "-s:128:128-n32:64"
)
for source_name, target_name in zip(sys.argv[1::2], sys.argv[2::2]):
    source = pathlib.Path(source_name).read_text()
    target = pathlib.Path(target_name)
    source, dl_count = re.subn(
        r'^target datalayout = ".*"$',
        f'target datalayout = "{data_layout}"',
        source,
        count=1,
        flags=re.MULTILINE,
    )
    source, triple_count = re.subn(
        r'^target triple = ".*"$',
        'target triple = "cellspu-unknown-elf"',
        source,
        count=1,
        flags=re.MULTILINE,
    )
    if dl_count != 1 or triple_count != 1:
        raise SystemExit(
            f"{source_name} must contain exactly one target triple and data layout"
        )
    target.write_text(source)
PY

# Use the maintained SPU GCC ABI as a caller for narrow integer returns. This
# small C bridge exists only inside the smoke fixture; it is not compiler code.
cat >"$tmp/abi_bridge.c" <<'C'
extern short max_i16(short lhs, short rhs);
extern unsigned short max_u16(unsigned short lhs, unsigned short rhs);

int gcc_call_max_i16(short lhs, short rhs) {
    return max_i16(lhs, rhs);
}

unsigned int gcc_call_max_u16(unsigned short lhs, unsigned short rhs) {
    return max_u16(lhs, rhs);
}
C
"$spu_cc" -O0 -c -o "$tmp/abi_bridge.o" "$tmp/abi_bridge.c"

python3 - "$tmp/stack_arg_bridge.c" <<'PY'
from pathlib import Path
import sys

params = ", ".join(["unsigned int"] * 73)
args = ", ".join(["0"] * 72 + ["0x12345678"])
Path(sys.argv[1]).write_text(
    f"extern unsigned int rust_last_arg({params});\n"
    f"extern unsigned int rust_forward_last_arg({params});\n"
    "unsigned int gcc_call_rust_last_arg(void) {\n"
    f"    return rust_last_arg({args});\n"
    "}\n"
    "unsigned int gcc_call_rust_forward_last_arg(void) {\n"
    f"    return rust_forward_last_arg({args});\n"
    "}\n"
)
PY
"$spu_cc" -O0 -c -o "$tmp/stack_arg_bridge.o" "$tmp/stack_arg_bridge.c"

cat >"$tmp/start.s" <<'ASM'
.text
.p2align 3
.globl _start
.type _start,@function
_start:
  # Keep the downward-growing frame within the 256 KiB local store.
  ilhu $1, 3
  iohl $1, 0xf000
  il $3, 0x1234
  il $4, 0x5678
  brsl $lr, add_u32
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 0x5678
  brsl $lr, sub_u32
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 0x5678
  brsl $lr, and_u32
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 0x5678
  brsl $lr, or_u32
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 0x5678
  brsl $lr, xor_u32
  wrch $ch28, $3
  il $3, 0x1234
  brsl $lr, increment_u32
  wrch $ch28, $3
  brsl $lr, constant_u32
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 0x1234
  brsl $lr, eq_u32
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 0x5678
  brsl $lr, eq_u32
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 0x5678
  brsl $lr, max_u32
  wrch $ch28, $3
  ilhu $3, 0
  iohl $3, 0x9876
  il $4, 0x5678
  brsl $lr, max_u32
  wrch $ch28, $3
  il $3, -2
  il $4, 5
  brsl $lr, max_i32
  wrch $ch28, $3
  il $3, 7
  il $4, -3
  brsl $lr, max_i32
  wrch $ch28, $3
  ila $3, fixture
  brsl $lr, load_word
  wrch $ch28, $3
  ila $3, fixture+12
  brsl $lr, load_word
  wrch $ch28, $3
  ila $3, fixture+4
  ilhu $4, 0xaabb
  iohl $4, 0xccdd
  brsl $lr, store_word
  ila $3, fixture
  brsl $lr, load_word
  wrch $ch28, $3
  ila $3, fixture+4
  brsl $lr, load_word
  wrch $ch28, $3
  ila $3, fixture+8
  brsl $lr, load_word
  wrch $ch28, $3
  ila $3, fixture+12
  brsl $lr, load_word
  wrch $ch28, $3
  il $3, -2
  il $4, 5
  brsl $lr, gcc_call_max_i16
  wrch $ch28, $3
  il $3, 7
  il $4, -3
  brsl $lr, gcc_call_max_i16
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 0x5678
  brsl $lr, gcc_call_max_u16
  wrch $ch28, $3
  ilhu $3, 0
  iohl $3, 0x9876
  il $4, 0x5678
  brsl $lr, gcc_call_max_u16
  wrch $ch28, $3
  brsl $lr, gcc_call_rust_last_arg
  wrch $ch28, $3
  brsl $lr, gcc_call_rust_forward_last_arg
  wrch $ch28, $3
  brsl $lr, rust_call_last_arg
  wrch $ch28, $3
  il $3, 0
  brsl $lr, sum_to_n
  wrch $ch28, $3
  il $3, 1
  brsl $lr, sum_to_n
  wrch $ch28, $3
  il $3, 5
  brsl $lr, sum_to_n
  wrch $ch28, $3
  il $3, 10
  brsl $lr, sum_to_n
  wrch $ch28, $3
  il $3, 0
  brsl $lr, sum_steps_opt
  wrch $ch28, $3
  il $3, 1
  brsl $lr, sum_steps_opt
  wrch $ch28, $3
  il $3, 2
  brsl $lr, sum_steps_opt
  wrch $ch28, $3
  il $3, 5
  brsl $lr, sum_steps_opt
  wrch $ch28, $3
  il $3, 10
  brsl $lr, sum_steps_opt
  wrch $ch28, $3
  il $3, 5
  il $4, 5
  brsl $lr, branch_eq
  wrch $ch28, $3
  il $3, 5
  il $4, 6
  brsl $lr, branch_eq
  wrch $ch28, $3
  il $3, 5
  il $4, 5
  brsl $lr, branch_ne
  wrch $ch28, $3
  il $3, 5
  il $4, 6
  brsl $lr, branch_ne
  wrch $ch28, $3
  il $3, -2
  il $4, 5
  brsl $lr, branch_slt
  wrch $ch28, $3
  il $3, 5
  il $4, -2
  brsl $lr, branch_slt
  wrch $ch28, $3
  il $3, -2
  il $4, -2
  brsl $lr, branch_sle
  wrch $ch28, $3
  il $3, 5
  il $4, -2
  brsl $lr, branch_sle
  wrch $ch28, $3
  il $3, 5
  il $4, -2
  brsl $lr, branch_sge
  wrch $ch28, $3
  il $3, -2
  il $4, 5
  brsl $lr, branch_sge
  wrch $ch28, $3
  il $3, 5
  ilhu $4, 0x8000
  brsl $lr, branch_ult
  wrch $ch28, $3
  ilhu $3, 0x8000
  il $4, 5
  brsl $lr, branch_ult
  wrch $ch28, $3
  il $3, 5
  il $4, 5
  brsl $lr, branch_ule
  wrch $ch28, $3
  ilhu $3, 0x8000
  il $4, 5
  brsl $lr, branch_ule
  wrch $ch28, $3
  ilhu $3, 0x8000
  il $4, 5
  brsl $lr, branch_uge
  wrch $ch28, $3
  il $3, 5
  ilhu $4, 0x8000
  brsl $lr, branch_uge
  wrch $ch28, $3
  il $3, 5
  il $4, 5
  brsl $lr, branch_eq_i16
  wrch $ch28, $3
  il $3, 5
  il $4, 6
  brsl $lr, branch_eq_i16
  wrch $ch28, $3
  il $3, 5
  il $4, 5
  brsl $lr, branch_ne_i16
  wrch $ch28, $3
  il $3, 5
  il $4, 6
  brsl $lr, branch_ne_i16
  wrch $ch28, $3
  il $3, -2
  il $4, 5
  brsl $lr, branch_slt_i16
  wrch $ch28, $3
  il $3, 5
  il $4, -2
  brsl $lr, branch_slt_i16
  wrch $ch28, $3
  il $3, -2
  il $4, -2
  brsl $lr, branch_sle_i16
  wrch $ch28, $3
  il $3, 5
  il $4, -2
  brsl $lr, branch_sle_i16
  wrch $ch28, $3
  il $3, 5
  il $4, -2
  brsl $lr, branch_sge_i16
  wrch $ch28, $3
  il $3, -2
  il $4, 5
  brsl $lr, branch_sge_i16
  wrch $ch28, $3
  il $3, 5
  il $4, 0
  iohl $4, 0x8000
  brsl $lr, branch_ult_u16
  wrch $ch28, $3
  il $3, 0
  iohl $3, 0x8000
  il $4, 5
  brsl $lr, branch_ult_u16
  wrch $ch28, $3
  il $3, 5
  il $4, 5
  brsl $lr, branch_ule_u16
  wrch $ch28, $3
  il $3, 0
  iohl $3, 0x8000
  il $4, 5
  brsl $lr, branch_ule_u16
  wrch $ch28, $3
  il $3, 0
  iohl $3, 0x8000
  il $4, 5
  brsl $lr, branch_uge_u16
  wrch $ch28, $3
  il $3, 5
  il $4, 0
  iohl $4, 0x8000
  brsl $lr, branch_uge_u16
  wrch $ch28, $3
  il $3, 0x1234
  brsl $lr, shift_left_const
  wrch $ch28, $3
  ilhu $3, 0x8000
  brsl $lr, shift_right_const
  wrch $ch28, $3
  il $3, -16
  brsl $lr, shift_arithmetic_const
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 33
  brsl $lr, shift_left_dynamic
  wrch $ch28, $3
  ilhu $3, 0x8000
  il $4, 33
  brsl $lr, shift_right_dynamic
  wrch $ch28, $3
  il $3, -16
  il $4, 36
  brsl $lr, shift_arithmetic_dynamic
  wrch $ch28, $3
  il $3, 0x1234
  il $4, 32
  brsl $lr, shift_left_dynamic
  wrch $ch28, $3
  ilhu $3, 0x1234
  iohl $3, 0x5678
  il $4, 3
  brsl $lr, wrapping_mul
  wrch $ch28, $3
  il $3, -2
  il $4, 2
  brsl $lr, wrapping_mul
  wrch $ch28, $3
  il $3, 0x7fff
  brsl $lr, leading_zero_count
  wrch $ch28, $3
  il $3, 0
  brsl $lr, leading_zero_count
  wrch $ch28, $3
  ilhu $3, 0x8000
  brsl $lr, trailing_zero_count
  wrch $ch28, $3
  il $3, 0x100
  brsl $lr, trailing_zero_count
  wrch $ch28, $3
  il $3, 0
  brsl $lr, trailing_zero_count
  wrch $ch28, $3
  ilhu $3, 0x1234
  iohl $3, 0x5678
  brsl $lr, population_count
  wrch $ch28, $3
  il $3, -1
  brsl $lr, population_count
  wrch $ch28, $3
  il $3, 0
  brsl $lr, population_count
  wrch $ch28, $3
  ilhu $3, 0xff00
  brsl $lr, leading_one_count
  wrch $ch28, $3
  il $3, -1
  brsl $lr, leading_one_count
  wrch $ch28, $3
  il $3, 0xf
  brsl $lr, trailing_one_count
  wrch $ch28, $3
  il $3, -1
  brsl $lr, trailing_one_count
  wrch $ch28, $3
  ilhu $3, 0x1234
  iohl $3, 0x5678
  il $4, 40
  brsl $lr, rotate_left
  wrch $ch28, $3
  ilhu $3, 0x1234
  iohl $3, 0x5678
  il $4, 40
  brsl $lr, rotate_right
  wrch $ch28, $3
  ilhu $3, 0x1234
  iohl $3, 0x5678
  brsl $lr, swap_bytes
  wrch $ch28, $3
  stop 0
.data
.p2align 4
fixture:
  .long 0x11111111
  .long 0x22222222
  .long 0x33333333
  .long 0x44444444
ASM

"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O0 \
    -verify-machineinstrs -filetype=obj "$tmp/scalar-spu.ll" -o "$tmp/scalar.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=obj "$tmp/optimized_loop-spu.ll" \
    -o "$tmp/optimized_loop.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O0 \
    -verify-machineinstrs -filetype=obj "$tmp/stack_args-spu.ll" \
    -o "$tmp/stack_args.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=obj "$tmp/dynamic_shift-spu.ll" \
    -o "$tmp/dynamic_shift.o"

# Build the same instruction streams through LLVM's text printer and GNU's
# assembler. Compare disassembly to cross-check the direct MC encodings; HBRA
# hints are deliberately ignored because the direct emitter currently writes
# an LNOP in their slots.
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O0 \
    -verify-machineinstrs -filetype=asm "$tmp/scalar-spu.ll" -o "$tmp/scalar.s"
"$spu_as" -o "$tmp/scalar-asm.o" "$tmp/scalar.s"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=asm "$tmp/optimized_loop-spu.ll" \
    -o "$tmp/optimized_loop.s"
"$spu_as" -o "$tmp/optimized_loop-asm.o" "$tmp/optimized_loop.s"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O0 \
    -verify-machineinstrs -filetype=asm "$tmp/stack_args-spu.ll" \
    -o "$tmp/stack_args.s"
"$spu_as" -o "$tmp/stack_args-asm.o" "$tmp/stack_args.s"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=asm "$tmp/dynamic_shift-spu.ll" \
    -o "$tmp/dynamic_shift.s"
"$spu_as" -o "$tmp/dynamic_shift-asm.o" "$tmp/dynamic_shift.s"

compare_direct_and_gnu_encoding() {
    local name=$1
    local direct_disassembly
    local gnu_disassembly
    direct_disassembly=$("$spu_objdump" -dr "$tmp/$name.o" | \
        sed -E '/file format/d; /[[:space:]](lnop|hbra)([[:space:]]|$)/d; /SPU_ADDR16[[:space:]]+\.text/d')
    gnu_disassembly=$("$spu_objdump" -dr "$tmp/$name-asm.o" | \
        sed -E '/file format/d; /[[:space:]](lnop|hbra)([[:space:]]|$)/d; /SPU_ADDR16[[:space:]]+\.text/d')
    if [[ "$direct_disassembly" != "$gnu_disassembly" ]]; then
        diff -u <(printf '%s\n' "$direct_disassembly") \
                <(printf '%s\n' "$gnu_disassembly") >&2 || true
        echo "LLVM direct object encodings differ from GNU SPU assembler output for $name" >&2
        return 1
    fi
}

compare_direct_and_gnu_encoding scalar
compare_direct_and_gnu_encoding optimized_loop
compare_direct_and_gnu_encoding stack_args
compare_direct_and_gnu_encoding dynamic_shift

stack_args_disassembly=$("$spu_objdump" -dr "$tmp/stack_args.o")
if ! grep -Eq 'lqd[[:space:]]+\$[0-9]+,160\(\$1\)' \
        <<<"$stack_args_disassembly" || \
   ! grep -Eq 'SPU_REL16[[:space:]]+rust_last_arg' <<<"$stack_args_disassembly"; then
    printf '%s\n' "$stack_args_disassembly" >&2
    echo "LLVM-generated stack-argument caller is missing the incoming 73rd-argument load or helper call" >&2
    exit 1
fi

scalar_relocations=$("$spu_readelf" -r "$tmp/scalar.o")
if ! grep -Fq 'R_SPU_ADDR16' <<<"$scalar_relocations"; then
    printf '%s\n' "$scalar_relocations" >&2
    echo "LLVM-generated scalar object is missing its constant-pool address relocations" >&2
    exit 1
fi

optimized_loop_disassembly=$("$spu_objdump" -dr "$tmp/optimized_loop.o")
if [[ "$optimized_loop_disassembly" != *'ai'*'3'* || \
      "$optimized_loop_disassembly" != *'brsl'*'opaque_step'* ]]; then
    echo "LLVM-generated optimized loop object is missing its helper operation or call" >&2
    printf '%s\n' "$optimized_loop_disassembly" >&2
    exit 1
fi

object_header=$("$spu_readelf" -h "$tmp/scalar.o")
for expected in \
    'Class:                             ELF32' \
    "Data:                              2's complement, big endian" \
    'Type:                              REL (Relocatable file)' \
    'Machine:                           SPU'; do
    if [[ "$object_header" != *"$expected"* ]]; then
        echo "LLVM-generated object is missing ELF header field: $expected" >&2
        exit 1
    fi
done

"$spu_objdump" -dr "$tmp/scalar.o" >"$tmp/scalar.object.dis"
for instruction in \
    'a[[:space:]]+\$3,\$3,\$4' \
    'sf[[:space:]]+\$3,\$4,\$3' \
    'and[[:space:]]+\$3,\$3,\$4' \
    'or[[:space:]]+\$3,\$3,\$4' \
    'xor[[:space:]]+\$3,\$3,\$4' \
    'ai[[:space:]]+\$3,\$3,1' \
    'il[[:space:]]+\$3,42' \
    'ceq[[:space:]]+\$3,\$3,\$4' \
    'andi[[:space:]]+\$3,\$3,1' \
    'clgt[[:space:]]+\$3,\$3,\$4' \
    'cgt[[:space:]]+\$3,\$3,\$4' \
    'clgth[[:space:]]+\$3,\$3,\$4' \
    'cgth[[:space:]]+\$3,\$3,\$4' \
    'brnz[[:space:]]+\$3,' \
    'brz[[:space:]]+\$3,' \
    'brhnz[[:space:]]+\$3,' \
    'rotqby[[:space:]]+\$3,\$3,\$4' \
    'cwd[[:space:]]+\$6,0\(\$4\)' \
    'shufb[[:space:]]+\$3,\$3,\$5,\$6' \
    'stqd[[:space:]]+\$0,16\(\$1\)' \
    'bi[[:space:]]+\$0'; do
    if ! grep -Eq "$instruction" "$tmp/scalar.object.dis"; then
        cat "$tmp/scalar.object.dis" >&2
        echo "LLVM-generated object is missing expected instruction: $instruction" >&2
        exit 1
    fi
done

"$spu_as" -o "$tmp/start.o" "$tmp/start.s"
"$spu_ld" -e _start -o "$tmp/scalar.elf" \
    "$tmp/start.o" "$tmp/abi_bridge.o" "$tmp/stack_arg_bridge.o" \
    "$tmp/scalar.o" "$tmp/optimized_loop.o" "$tmp/stack_args.o" \
    "$tmp/dynamic_shift.o"

executable_header=$("$spu_readelf" -h "$tmp/scalar.elf")
if [[ "$executable_header" != *'Type:                              EXEC (Executable file)'* || \
      "$executable_header" != *'Machine:                           SPU'* ]]; then
    echo "linked LLVM-generated program is not an SPU executable" >&2
    exit 1
fi

if ! (cd "$tmp" && ANERG_MBOX="$tmp/mailbox" \
      timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" "$tmp/scalar.elf") \
      >"$tmp/emulator.log" 2>&1; then
    cat "$tmp/emulator.log" >&2
    echo "LLVM-generated SPU program failed or timed out in the emulator" >&2
    exit 1
fi
if ! grep -Fq '####### stop instruction reached:' "$tmp/emulator.log"; then
    cat "$tmp/emulator.log" >&2
    echo "LLVM-generated SPU program did not reach stop" >&2
    exit 1
fi

byte_count=$(wc -c <"$tmp/mailbox")
actual=$(od -An -v -tx1 "$tmp/mailbox" | tr -d '[:space:]')
expected=000068acffffbbbc000012300000567c0000444c000012350000002a
expected+=0000000100000000
expected+=0000567800009876
expected+=0000000500000007
expected+=1111111144444444
expected+=11111111aabbccdd3333333344444444
expected+=00000005000000070000567800009876
expected+=123456781234567812345678
expected+=00000000000000000000000a0000002d
expected+=000000000000000300000007000000190000004b
expected+=00000001000000000000000000000001
expected+=00000001000000000000000100000000
expected+=00000001000000000000000100000000
expected+=00000001000000000000000100000000
expected+=00000001000000000000000000000001
expected+=00000001000000000000000100000000
expected+=00000001000000000000000100000000
expected+=00000001000000000000000100000000
expected+=000091a004000000ffffffff
expected+=0000246840000000ffffffff
expected+=00001234
expected+=369d0368fffffffc
expected+=00000011000000200000001f00000008000000200000000d000000200000000000000008000000200000000400000020345678127812345678563412
if [[ "$byte_count" != 364 || "$actual" != "$expected" ]]; then
    cat "$tmp/emulator.log" >&2
    echo "expected mailbox words $expected; got ${actual:-<empty>} ($byte_count bytes)" >&2
    exit 1
fi

printf 'LLVM 23.1.1 CellSPU scalar arithmetic, byte-swap, shifts, rotates, bit-count, branch, loop, call, stack-argument ABI, and pointer-memory subset: direct LLVM ELF32 EM_SPU objects; emulator returned ninety-one expected words and reached stop\n'
