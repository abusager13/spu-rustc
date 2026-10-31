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
pub unsafe extern "C" fn load_u8(pointer: *const u8) -> u8 {
    unsafe { *pointer }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn load_i8(pointer: *const i8) -> i8 {
    unsafe { *pointer }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn load_u16(pointer: *const u16) -> u16 {
    unsafe { *pointer }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn load_i16(pointer: *const i16) -> i16 {
    unsafe { *pointer }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn store_u8(pointer: *mut u8, value: u8) {
    unsafe { *pointer = value; }
}

#[repr(C, packed)]
pub struct PackedU16 {
    _padding: u8,
    value: u16,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn load_packed_u16(pointer: *const PackedU16) -> u16 {
    unsafe { (*pointer).value }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn store_packed_u16(pointer: *mut PackedU16, value: u16) {
    unsafe { (*pointer).value = value; }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn load_u64_high(pointer: *const u64) -> u32 {
    (unsafe { *pointer } >> 32) as u32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn load_u64_low(pointer: *const u64) -> u32 {
    unsafe { *pointer as u32 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn store_u64_halves(pointer: *mut u64, high: u32, low: u32) {
    unsafe { *pointer = ((high as u64) << 32) | low as u64; }
}

#[repr(C, packed)]
pub struct PackedU64 {
    _padding: u8,
    value: u64,
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn load_packed_u64_high(pointer: *const PackedU64) -> u32 {
    (unsafe { (*pointer).value } >> 32) as u32
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn load_packed_u64_low(pointer: *const PackedU64) -> u32 {
    unsafe { (*pointer).value as u32 }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn store_packed_u64(pointer: *mut PackedU64, high: u32, low: u32) {
    unsafe { (*pointer).value = ((high as u64) << 32) | low as u64; }
}

#[unsafe(no_mangle)]
pub extern "C" fn add_u64_abi(lhs: u64, rhs: u64) -> u64 {
    lhs.wrapping_add(rhs)
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

#[unsafe(no_mangle)]
pub extern "C" fn branch_eq_u64(lhs: u64, rhs: u64) -> u32 {
    if lhs == rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ne_u64(lhs: u64, rhs: u64) -> u32 {
    if lhs != rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_slt_i64(lhs: i64, rhs: i64) -> u32 {
    if lhs < rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_sle_i64(lhs: i64, rhs: i64) -> u32 {
    if lhs <= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_sgt_i64(lhs: i64, rhs: i64) -> u32 {
    if lhs > rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_sge_i64(lhs: i64, rhs: i64) -> u32 {
    if lhs >= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ult_u64(lhs: u64, rhs: u64) -> u32 {
    if lhs < rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ule_u64(lhs: u64, rhs: u64) -> u32 {
    if lhs <= rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_ugt_u64(lhs: u64, rhs: u64) -> u32 {
    if lhs > rhs { 1 } else { 0 }
}

#[unsafe(no_mangle)]
pub extern "C" fn branch_uge_u64(lhs: u64, rhs: u64) -> u32 {
    if lhs >= rhs { 1 } else { 0 }
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

#[unsafe(no_mangle)]
pub static SPU_RELOC_TARGET: [u8; 4] = [0x5a, 0x17, 0xc0, 0xde];

#[unsafe(no_mangle)]
pub static SPU_RELOC_POINTER: &[u8; 4] = &SPU_RELOC_TARGET;

#[unsafe(no_mangle)]
pub extern "C" fn read_spu_reloc_pointer() -> u32 {
    let pointer = unsafe {
        core::ptr::read_volatile(core::ptr::addr_of!(SPU_RELOC_POINTER))
    };
    let bytes = pointer.as_ptr();
    unsafe {
        ((core::ptr::read_volatile(bytes) as u32) << 24)
            | ((core::ptr::read_volatile(bytes.add(1)) as u32) << 16)
            | ((core::ptr::read_volatile(bytes.add(2)) as u32) << 8)
            | (core::ptr::read_volatile(bytes.add(3)) as u32)
    }
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

cat >"$tmp/vector_abi.rs" <<'RUST'
#![no_std]
#![feature(repr_simd, core_intrinsics)]
#![allow(internal_features, improper_ctypes_definitions, unused_variables)]

#[repr(simd)]
#[derive(Clone, Copy)]
pub struct U32x4([u32; 4]);

#[unsafe(no_mangle)]
pub extern "C" fn cellspu_vector_add(lhs: U32x4, rhs: U32x4) -> U32x4 {
    unsafe { core::intrinsics::simd::simd_add(lhs, rhs) }
}
RUST
python3 - "$tmp/vector_abi.rs" <<'PY'
from pathlib import Path
import sys

params = ", ".join(f"a{i}: U32x4" for i in range(73))
Path(sys.argv[1]).open("a").write(
    "\n#[inline(never)]\n#[unsafe(no_mangle)]\n"
    f'pub extern "C" fn cellspu_vector_last_arg({params}) -> U32x4 {{ a72 }}\n'
)
PY
RUSTC_BOOTSTRAP=1 "$rustc" --crate-type=lib --emit=llvm-ir \
    -C panic=abort -C opt-level=1 \
    -o "$tmp/vector_abi.ll" "$tmp/vector_abi.rs"

cat >"$tmp/integer_division.rs" <<'RUST'
#![no_std]
#![feature(core_intrinsics)]
#![allow(internal_features)]

unsafe extern "C" {
    fn cellspu_external_target(value: u32) -> u32;
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cellspu_external_call(value: u32) -> u32 {
    unsafe { cellspu_external_target(value) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cellspu_udiv32(lhs: u32, rhs: u32) -> u32 {
    unsafe { core::intrinsics::unchecked_div(lhs, rhs) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cellspu_urem32(lhs: u32, rhs: u32) -> u32 {
    unsafe { core::intrinsics::unchecked_rem(lhs, rhs) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cellspu_sdiv32(lhs: i32, rhs: i32) -> i32 {
    unsafe { core::intrinsics::unchecked_div(lhs, rhs) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cellspu_srem32(lhs: i32, rhs: i32) -> i32 {
    unsafe { core::intrinsics::unchecked_rem(lhs, rhs) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cellspu_udiv64(lhs: u64, rhs: u64) -> u64 {
    unsafe { core::intrinsics::unchecked_div(lhs, rhs) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cellspu_urem64(lhs: u64, rhs: u64) -> u64 {
    unsafe { core::intrinsics::unchecked_rem(lhs, rhs) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cellspu_sdiv64(lhs: i64, rhs: i64) -> i64 {
    unsafe { core::intrinsics::unchecked_div(lhs, rhs) }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn cellspu_srem64(lhs: i64, rhs: i64) -> i64 {
    unsafe { core::intrinsics::unchecked_rem(lhs, rhs) }
}
RUST
RUSTC_BOOTSTRAP=1 "$rustc" --crate-type=lib --emit=llvm-ir \
    -C panic=abort -C opt-level=1 \
    -o "$tmp/integer_division.ll" "$tmp/integer_division.rs"

cat >"$tmp/float_math.rs" <<'RUST'
#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn rust_f32_add(lhs: f32, rhs: f32) -> f32 {
    lhs + rhs
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_f32_sub(lhs: f32, rhs: f32) -> f32 {
    lhs - rhs
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_f32_mul(lhs: f32, rhs: f32) -> f32 {
    lhs * rhs
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_f64_add(lhs: f64, rhs: f64) -> f64 {
    lhs + rhs
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_f64_sub(lhs: f64, rhs: f64) -> f64 {
    lhs - rhs
}

#[unsafe(no_mangle)]
pub extern "C" fn rust_f64_mul(lhs: f64, rhs: f64) -> f64 {
    lhs * rhs
}
RUST
"$rustc" --crate-type=lib --emit=llvm-ir -C panic=abort -C opt-level=1 \
    -o "$tmp/float_math.ll" "$tmp/float_math.rs"

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
    "$tmp/dynamic_shift.ll" "$tmp/dynamic_shift-spu.ll" \
    "$tmp/vector_abi.ll" "$tmp/vector_abi-spu.ll" \
    "$tmp/integer_division.ll" "$tmp/integer_division-spu.ll" \
    "$tmp/float_math.ll" "$tmp/float_math-spu.ll" <<'PY'
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

cat >"$tmp/vector_abi_bridge.c" <<'C'
#include <spu_intrinsics.h>

typedef __vector unsigned int vec4u32;
extern vec4u32 cellspu_vector_add(vec4u32 lhs, vec4u32 rhs);

unsigned int cellspu_vector_abi_test(void) {
    vec4u32 lhs = {1, 2, 0x7fffffff, 0xffffffff};
    vec4u32 rhs = {4, 8, 1, 2};
    vec4u32 result = cellspu_vector_add(lhs, rhs);

    return !(spu_extract(result, 0) == 5 &&
             spu_extract(result, 1) == 10 &&
             spu_extract(result, 2) == 0x80000000 &&
             spu_extract(result, 3) == 1);
}
C
"$spu_cc" -O0 -c -o "$tmp/vector_abi_bridge.o" "$tmp/vector_abi_bridge.c"

python3 - "$tmp/vector_stack_bridge.c" <<'PY'
from pathlib import Path
import sys

params = ", ".join(f"vec4u32 a{i}" for i in range(73))
args = ", ".join(["zero"] * 72 + ["last"])
Path(sys.argv[1]).write_text(
    "#include <spu_intrinsics.h>\n"
    "typedef __vector unsigned int vec4u32;\n"
    f"extern vec4u32 cellspu_vector_last_arg({params});\n"
    "unsigned int cellspu_vector_stack_test(void) {\n"
    "    vec4u32 zero = {0, 0, 0, 0};\n"
    "    vec4u32 last = {0x11111111, 0x22222222, 0x33333333, 0x44444444};\n"
    f"    vec4u32 result = cellspu_vector_last_arg({args});\n"
    "    return !(spu_extract(result, 0) == 0x11111111 &&\n"
    "             spu_extract(result, 1) == 0x22222222 &&\n"
    "             spu_extract(result, 2) == 0x33333333 &&\n"
    "             spu_extract(result, 3) == 0x44444444);\n"
    "}\n"
)
PY
"$spu_cc" -O0 -c -o "$tmp/vector_stack_bridge.o" \
    "$tmp/vector_stack_bridge.c"

cat >"$tmp/integer_division_bridge.c" <<'C'
#include <stdint.h>

extern uint32_t cellspu_udiv32(uint32_t lhs, uint32_t rhs);
extern uint32_t cellspu_urem32(uint32_t lhs, uint32_t rhs);
extern int32_t cellspu_sdiv32(int32_t lhs, int32_t rhs);
extern int32_t cellspu_srem32(int32_t lhs, int32_t rhs);
extern uint64_t cellspu_udiv64(uint64_t lhs, uint64_t rhs);
extern uint64_t cellspu_urem64(uint64_t lhs, uint64_t rhs);
extern int64_t cellspu_sdiv64(int64_t lhs, int64_t rhs);
extern int64_t cellspu_srem64(int64_t lhs, int64_t rhs);

uint32_t cellspu_external_target(uint32_t value) { return value; }
uint32_t __udivsi3(uint32_t lhs, uint32_t rhs) { return lhs / rhs; }
uint32_t __umodsi3(uint32_t lhs, uint32_t rhs) { return lhs % rhs; }
int32_t __divsi3(int32_t lhs, int32_t rhs) { return lhs / rhs; }
int32_t __modsi3(int32_t lhs, int32_t rhs) { return lhs % rhs; }

unsigned int cellspu_integer_division_test(void) {
    const int64_t i64_min = (-9223372036854775807LL - 1);
    return !(cellspu_udiv32(100, 7) == 14 &&
             cellspu_udiv32(0xffffffffu, 3) == 1431655765u &&
             cellspu_udiv32(3, 7) == 0 &&
             cellspu_urem32(100, 7) == 2 &&
             cellspu_urem32(0xffffffffu, 3) == 0 &&
             cellspu_sdiv32(-100, 7) == -14 &&
             cellspu_sdiv32(100, -7) == -14 &&
             cellspu_sdiv32((-2147483647 - 1), 3) == -715827882 &&
             cellspu_srem32(-100, 7) == -2 &&
             cellspu_srem32(100, -7) == 2 &&
             cellspu_srem32((-2147483647 - 1), 3) == -2 &&
             cellspu_udiv64(0xffffffffffffffffull, 3) ==
                 0x5555555555555555ull &&
             cellspu_urem64(0xffffffffffffffffull, 3) == 0 &&
             cellspu_sdiv64(i64_min, 3) == -3074457345618258602ll &&
             cellspu_srem64(i64_min, 3) == -2 &&
             cellspu_sdiv64(9223372036854775807ll, -7) ==
                 -1317624576693539401ll &&
             cellspu_srem64(-100, -7) == -2);
}
C
"$spu_cc" -O1 -c -o "$tmp/integer_division_bridge.o" \
    "$tmp/integer_division_bridge.c"

cat >"$tmp/i64_compare_bridge.c" <<'C'
extern unsigned int branch_eq_u64(unsigned long long lhs, unsigned long long rhs);
extern unsigned int branch_ne_u64(unsigned long long lhs, unsigned long long rhs);
extern unsigned int branch_slt_i64(long long lhs, long long rhs);
extern unsigned int branch_sle_i64(long long lhs, long long rhs);
extern unsigned int branch_sgt_i64(long long lhs, long long rhs);
extern unsigned int branch_sge_i64(long long lhs, long long rhs);
extern unsigned int branch_ult_u64(unsigned long long lhs, unsigned long long rhs);
extern unsigned int branch_ule_u64(unsigned long long lhs, unsigned long long rhs);
extern unsigned int branch_ugt_u64(unsigned long long lhs, unsigned long long rhs);
extern unsigned int branch_uge_u64(unsigned long long lhs, unsigned long long rhs);

unsigned int gcc_compare_i64(void) {
    long long signed_min = (-9223372036854775807LL - 1LL);
    unsigned long long unsigned_low = 0x00000000ffffffffULL;
    unsigned long long unsigned_high = 0x0000000100000000ULL;
    unsigned int result = 0;

    result |= branch_eq_u64(5ULL, 5ULL) << 0;
    result |= branch_eq_u64(5ULL, 6ULL) << 1;
    result |= branch_ne_u64(5ULL, 6ULL) << 2;
    result |= branch_ne_u64(5ULL, 5ULL) << 3;
    result |= branch_slt_i64(signed_min, 0LL) << 4;
    result |= branch_slt_i64(0LL, signed_min) << 5;
    result |= branch_sle_i64(signed_min, 0LL) << 6;
    result |= branch_sle_i64(0LL, signed_min) << 7;
    result |= branch_sgt_i64(0LL, signed_min) << 8;
    result |= branch_sgt_i64(signed_min, 0LL) << 9;
    result |= branch_sge_i64(0LL, signed_min) << 10;
    result |= branch_sge_i64(signed_min, 0LL) << 11;
    result |= branch_ult_u64(unsigned_low, unsigned_high) << 12;
    result |= branch_ult_u64(unsigned_high, unsigned_low) << 13;
    result |= branch_ule_u64(unsigned_low, unsigned_high) << 14;
    result |= branch_ule_u64(unsigned_high, unsigned_low) << 15;
    result |= branch_ugt_u64(unsigned_high, unsigned_low) << 16;
    result |= branch_ugt_u64(unsigned_low, unsigned_high) << 17;
    result |= branch_uge_u64(unsigned_high, unsigned_low) << 18;
    result |= branch_uge_u64(unsigned_low, unsigned_high) << 19;
    return result;
}
C
"$spu_cc" -O0 -c -o "$tmp/i64_compare_bridge.o" "$tmp/i64_compare_bridge.c"

cat >"$tmp/narrow_memory_bridge.c" <<'C'
extern unsigned char load_u8(const unsigned char *pointer);
extern signed char load_i8(const signed char *pointer);
extern unsigned short load_u16(const unsigned short *pointer);
extern short load_i16(const short *pointer);
extern void store_u8(unsigned char *pointer, unsigned char value);
struct __attribute__((packed)) packed_u16 { unsigned char padding; unsigned short value; };
extern unsigned short load_packed_u16(const struct packed_u16 *pointer);
extern void store_packed_u16(struct packed_u16 *pointer, unsigned short value);
extern unsigned int load_u64_high(const unsigned long long *pointer);
extern unsigned int load_u64_low(const unsigned long long *pointer);
extern void store_u64_halves(unsigned long long *pointer, unsigned int high,
                             unsigned int low);
struct __attribute__((packed)) packed_u64 { unsigned char padding; unsigned long long value; };
extern unsigned int load_packed_u64_high(const struct packed_u64 *pointer);
extern unsigned int load_packed_u64_low(const struct packed_u64 *pointer);
extern void store_packed_u64(struct packed_u64 *pointer, unsigned int high,
                             unsigned int low);
extern unsigned long long add_u64_abi(unsigned long long lhs,
                                      unsigned long long rhs);

unsigned int gcc_read_u8_samples(unsigned char *bytes) {
    return ((unsigned int)load_u8(bytes) << 24) |
           ((unsigned int)load_u8(bytes + 15) << 16) |
           ((unsigned int)load_u8(bytes + 16) << 8) |
           (unsigned int)load_u8(bytes + 31);
}

unsigned int gcc_read_i8_samples(signed char *bytes) {
    unsigned int first = (unsigned int)(int)load_i8(bytes);
    unsigned int second = (unsigned int)(int)load_i8(bytes + 2);
    return (first << 16) | (second & 0xffff);
}

unsigned int gcc_read_u16_samples(unsigned char *bytes) {
    return ((unsigned int)load_u16((unsigned short *)(bytes + 0)) << 16) |
           (unsigned int)load_u16((unsigned short *)(bytes + 2));
}

unsigned int gcc_read_u16_tail(unsigned char *bytes) {
    return ((unsigned int)load_u16((unsigned short *)(bytes + 14)) << 16) |
           (unsigned int)load_u16((unsigned short *)(bytes + 30));
}

int gcc_read_i16_zero(unsigned char *bytes) {
    return (int)load_i16((short *)(bytes + 0));
}

int gcc_read_i16_two(unsigned char *bytes) {
    return (int)load_i16((short *)(bytes + 2));
}

int gcc_read_i16_tail(unsigned char *bytes) {
    return (int)load_i16((short *)(bytes + 30));
}

unsigned int gcc_read_packed_u16(unsigned char *bytes) {
    struct packed_u16 *packed = (struct packed_u16 *)(bytes + 14);
    return (unsigned int)load_packed_u16(packed);
}

unsigned int gcc_store_u8_and_read_neighbors(unsigned char *bytes) {
    store_u8(bytes + 5, 0xab);
    return ((unsigned int)bytes[4] << 16) |
           ((unsigned int)bytes[5] << 8) | bytes[6];
}

unsigned int gcc_store_packed_u16_and_read_neighbors(unsigned char *bytes) {
    struct packed_u16 *packed = (struct packed_u16 *)(bytes + 14);
    store_packed_u16(packed, 0xcdef);
    return ((unsigned int)bytes[14] << 24) |
           ((unsigned int)bytes[15] << 16) |
           ((unsigned int)bytes[16] << 8) | bytes[17];
}

unsigned int gcc_read_packed_u16_after_store(unsigned char *bytes) {
    struct packed_u16 *packed = (struct packed_u16 *)(bytes + 14);
    return (unsigned int)load_packed_u16(packed);
}

unsigned int gcc_read_u64_high(unsigned char *bytes) {
    return load_u64_high((unsigned long long *)(bytes + 8));
}

unsigned int gcc_read_u64_low(unsigned char *bytes) {
    return load_u64_low((unsigned long long *)(bytes + 8));
}

unsigned int gcc_store_u64_and_read_neighbors(unsigned char *bytes) {
    store_u64_halves((unsigned long long *)(bytes + 8), 0xa1b2c3d4, 0xe5f60718);
    return ((unsigned int)bytes[7] << 24) |
           ((unsigned int)bytes[8] << 16) |
           ((unsigned int)bytes[15] << 8) | bytes[16];
}

unsigned int gcc_read_u64_high_after_store(unsigned char *bytes) {
    return load_u64_high((unsigned long long *)(bytes + 8));
}

unsigned int gcc_read_u64_low_after_store(unsigned char *bytes) {
    return load_u64_low((unsigned long long *)(bytes + 8));
}

unsigned int gcc_read_packed_u64_high(unsigned char *bytes) {
    struct packed_u64 *packed = (struct packed_u64 *)(bytes + 12);
    return load_packed_u64_high(packed);
}

unsigned int gcc_read_packed_u64_low(unsigned char *bytes) {
    struct packed_u64 *packed = (struct packed_u64 *)(bytes + 12);
    return load_packed_u64_low(packed);
}

unsigned int gcc_store_packed_u64_and_read_neighbors(unsigned char *bytes) {
    struct packed_u64 *packed = (struct packed_u64 *)(bytes + 12);
    store_packed_u64(packed, 0x11223344, 0x55667788);
    return ((unsigned int)bytes[12] << 24) |
           ((unsigned int)bytes[13] << 16) |
           ((unsigned int)bytes[20] << 8) | bytes[21];
}

unsigned int gcc_read_packed_u64_high_after_store(unsigned char *bytes) {
    struct packed_u64 *packed = (struct packed_u64 *)(bytes + 12);
    return load_packed_u64_high(packed);
}

unsigned int gcc_read_packed_u64_low_after_store(unsigned char *bytes) {
    struct packed_u64 *packed = (struct packed_u64 *)(bytes + 12);
    return load_packed_u64_low(packed);
}

unsigned int gcc_add_u64_abi_high(void) {
    unsigned long long sum = add_u64_abi(0x12345678abcdef01ULL,
                                          0x1111111122222222ULL);
    return (unsigned int)(sum >> 32);
}

unsigned int gcc_add_u64_abi_low(void) {
    unsigned long long sum = add_u64_abi(0x12345678abcdef01ULL,
                                          0x1111111122222222ULL);
    return (unsigned int)sum;
}
C
"$spu_cc" -O0 -c -o "$tmp/narrow_memory_bridge.o" "$tmp/narrow_memory_bridge.c"

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
  brsl $lr, gcc_compare_i64
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_u8_samples
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_i8_samples
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_u16_samples
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_u16_tail
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_i16_zero
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_i16_two
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_i16_tail
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_packed_u16
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_store_u8_and_read_neighbors
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_store_packed_u16_and_read_neighbors
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_packed_u16_after_store
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_u64_high
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_u64_low
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_store_u64_and_read_neighbors
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_u64_high_after_store
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_u64_low_after_store
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_packed_u64_high
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_packed_u64_low
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_store_packed_u64_and_read_neighbors
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_packed_u64_high_after_store
  wrch $ch28, $3
  ila $3, narrow_fixture
  brsl $lr, gcc_read_packed_u64_low_after_store
  wrch $ch28, $3
  brsl $lr, gcc_add_u64_abi_high
  wrch $ch28, $3
  brsl $lr, gcc_add_u64_abi_low
  wrch $ch28, $3
  brsl $lr, read_spu_reloc_pointer
  wrch $ch28, $3
  stop 0
.data
.p2align 4
fixture:
  .long 0x11111111
  .long 0x22222222
  .long 0x33333333
  .long 0x44444444
.p2align 4
narrow_fixture:
  .byte 0x80, 0x7f, 0xff, 0x01, 0x12, 0x34, 0xfe, 0xdc
  .byte 0x00, 0x80, 0x55, 0xaa, 0xf0, 0x0f, 0x13, 0x37
  .byte 0x68, 0x24, 0x9a, 0xbc, 0xde, 0xf0, 0x11, 0x22
  .byte 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa
ASM

"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O0 \
    -verify-machineinstrs -filetype=obj "$tmp/scalar-spu.ll" -o "$tmp/scalar.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -mattr=+short-calls -O1 \
    -verify-machineinstrs -filetype=obj "$tmp/optimized_loop-spu.ll" \
    -o "$tmp/optimized_loop.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=obj "$tmp/optimized_loop-spu.ll" \
    -o "$tmp/optimized_loop_absolute.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O0 \
    -mattr=+short-calls \
    -verify-machineinstrs -filetype=obj "$tmp/stack_args-spu.ll" \
    -o "$tmp/stack_args.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=obj "$tmp/dynamic_shift-spu.ll" \
    -o "$tmp/dynamic_shift.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -mattr=+large_mem -O1 \
    -verify-machineinstrs -filetype=obj "$tmp/dynamic_shift-spu.ll" \
    -o "$tmp/dynamic_shift_large.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=obj "$tmp/vector_abi-spu.ll" \
    -o "$tmp/vector_abi.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=obj "$tmp/integer_division-spu.ll" \
    -o "$tmp/integer_division.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 \
    -mattr=+short-calls -O1 -verify-machineinstrs -filetype=obj \
    "$tmp/integer_division-spu.ll" -o "$tmp/integer_division_short.o"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=obj "$tmp/float_math-spu.ll" \
    -o "$tmp/float_math.o"

# Build the same instruction streams through LLVM's text printer and GNU's
# assembler. Compare disassembly to cross-check the direct MC encodings while
# filtering LNOP filler slots; branch-hint instructions are compared directly.
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O0 \
    -verify-machineinstrs -filetype=asm "$tmp/scalar-spu.ll" -o "$tmp/scalar.s"
"$spu_as" -o "$tmp/scalar-asm.o" "$tmp/scalar.s"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -mattr=+short-calls -O1 \
    -verify-machineinstrs -filetype=asm "$tmp/optimized_loop-spu.ll" \
    -o "$tmp/optimized_loop.s"
"$spu_as" -o "$tmp/optimized_loop-asm.o" "$tmp/optimized_loop.s"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -mattr=+short-calls -O0 \
    -verify-machineinstrs -filetype=asm "$tmp/stack_args-spu.ll" \
    -o "$tmp/stack_args.s"
"$spu_as" -o "$tmp/stack_args-asm.o" "$tmp/stack_args.s"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=asm "$tmp/dynamic_shift-spu.ll" \
    -o "$tmp/dynamic_shift.s"
"$spu_as" -o "$tmp/dynamic_shift-asm.o" "$tmp/dynamic_shift.s"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -mattr=+large_mem -O1 \
    -verify-machineinstrs -filetype=asm "$tmp/dynamic_shift-spu.ll" \
    -o "$tmp/dynamic_shift_large.s"
"$spu_as" -o "$tmp/dynamic_shift_large-asm.o" \
    "$tmp/dynamic_shift_large.s"
"$llc" -mtriple=cellspu-unknown-elf -mcpu=v0 -O1 \
    -verify-machineinstrs -filetype=asm "$tmp/float_math-spu.ll" \
    -o "$tmp/float_math.s"
"$spu_as" -o "$tmp/float_math-asm.o" "$tmp/float_math.s"

compare_direct_and_gnu_encoding() {
    local name=$1
    local direct_disassembly
    local gnu_disassembly
    direct_disassembly=$("$spu_objdump" -dr "$tmp/$name.o" | \
        sed -E '/file format/d; /[[:space:]]lnop([[:space:]]|$)/d; /SPU_ADDR16[[:space:]]+\.text/d')
    gnu_disassembly=$("$spu_objdump" -dr "$tmp/$name-asm.o" | \
        sed -E '/file format/d; /[[:space:]]lnop([[:space:]]|$)/d; /SPU_ADDR16[[:space:]]+\.text/d')
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
compare_direct_and_gnu_encoding dynamic_shift_large
compare_direct_and_gnu_encoding float_math

float_math_disassembly=$("$spu_objdump" -d "$tmp/float_math.o")
for instruction in fa fs fm dfa dfs dfm; do
    if ! grep -Eq "[[:space:]]${instruction}[[:space:]]" \
            <<<"$float_math_disassembly"; then
        printf '%s\n' "$float_math_disassembly" >&2
        echo "Rust floating-point operation did not select SPU ${instruction}" >&2
        exit 1
    fi
done

vector_disassembly=$("$spu_objdump" -dr "$tmp/vector_abi.o")
grep -Eq 'a[[:space:]]+\$3,\$4,\$3' <<<"$vector_disassembly" || {
    printf '%s\n' "$vector_disassembly" >&2
    echo "LLVM vector addition did not select native SPU a" >&2
    exit 1
}
cat >"$tmp/vector_abi_reference.s" <<'ASM'
.text
a $3,$4,$3
ASM
"$spu_as" -o "$tmp/vector_abi_reference.o" "$tmp/vector_abi_reference.s"
vector_reference=$("$spu_objdump" -d "$tmp/vector_abi_reference.o" | \
    awk '$6 == "a" { print $2 $3 $4 $5 }')
vector_actual=$("$spu_objdump" -d "$tmp/vector_abi.o" | \
    awk '$6 == "a" { print $2 $3 $4 $5 }')
[[ "$vector_actual" == "$vector_reference" ]] || {
    echo "LLVM vector addition encoding differs from GNU SPU binutils" >&2
    exit 1
}

integer_division_disassembly=$("$spu_objdump" -dr "$tmp/integer_division.o")
cat >"$tmp/brasl_reference.s" <<'ASM'
.text
.globl caller
caller:
  brasl $lr,target
  bi $lr
.globl target
target:
  stop 0
ASM
"$spu_as" -o "$tmp/brasl_reference.o" "$tmp/brasl_reference.s"
brasl_reference=$("$spu_objdump" -d "$tmp/brasl_reference.o" | \
    awk '$6 == "brasl" { print $2 $3 $4 $5; exit }')
brasl_actual=$("$spu_objdump" -d "$tmp/integer_division.o" | \
    awk '$6 == "brasl" { print $2 $3 $4 $5; exit }')
if [[ -z "$brasl_reference" || "$brasl_actual" != "$brasl_reference" ]]; then
    printf '%s\n' "$integer_division_disassembly" >&2
    echo "LLVM BRASL encoding differs from GNU SPU binutils" >&2
    exit 1
fi
integer_division_relocations=$("$spu_readelf" -Wr "$tmp/integer_division.o")
for helper in __divsi3 __udivsi3 __modsi3 __umodsi3 \
              __divdi3 __udivdi3 __moddi3 __umoddi3; do
    if ! awk -v helper="$helper" \
            '$3 == "R_SPU_ADDR16" && $5 == helper { found = 1 } \
             END { exit !found }' <<<"$integer_division_relocations"; then
        printf '%s\n' "$integer_division_relocations" >&2
        echo "LLVM default integer division object is missing the absolute call relocation for $helper" >&2
        exit 1
    fi
done
if ! awk '$3 == "R_SPU_ADDR16" && $5 == "cellspu_external_target" \
          { found = 1 } END { exit !found }' \
          <<<"$integer_division_relocations"; then
    printf '%s\n' "$integer_division_relocations" >&2
    echo "LLVM external-declaration call is missing its absolute call relocation" >&2
    exit 1
fi
integer_division_short_relocations=$(
    "$spu_readelf" -Wr "$tmp/integer_division_short.o")
for helper in __divsi3 __udivsi3 __modsi3 __umodsi3 \
              __divdi3 __udivdi3 __moddi3 __umoddi3; do
    if ! awk -v helper="$helper" \
            '$3 == "R_SPU_REL16" && $5 == helper { found = 1 } \
             END { exit !found }' <<<"$integer_division_short_relocations"; then
        printf '%s\n' "$integer_division_short_relocations" >&2
        echo "LLVM short-calls object is missing the relative call relocation for $helper" >&2
        exit 1
    fi
done
optimized_loop_absolute_disassembly=$(
    "$spu_objdump" -dr "$tmp/optimized_loop_absolute.o")
optimized_loop_absolute_relocations=$(
    "$spu_readelf" -Wr "$tmp/optimized_loop_absolute.o")
if ! grep -Fq 'brasl' <<<"$optimized_loop_absolute_disassembly" || \
   ! awk '$3 == "R_SPU_ADDR16" && $5 ~ /opaque_step/ \
          { found = 1 } END { exit !found }' \
          <<<"$optimized_loop_absolute_relocations"; then
    printf '%s\n' "$optimized_loop_absolute_disassembly" >&2
    printf '%s\n' "$optimized_loop_absolute_relocations" >&2
    echo "LLVM default intra-module call is missing absolute BRASL/R_SPU_ADDR16" >&2
    exit 1
fi

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
dynamic_shift_relocations=$("$spu_readelf" -r "$tmp/dynamic_shift.o")
for relocation in R_SPU_ADDR18 R_SPU_ADDR32; do
    if ! grep -Fq "$relocation" <<<"$dynamic_shift_relocations"; then
        printf '%s\n' "$dynamic_shift_relocations" >&2
        echo "LLVM-generated Rust static-pointer object is missing $relocation" >&2
        exit 1
    fi
done
if ! grep -Fq 'SPU_RELOC_POINTER' <<<"$dynamic_shift_relocations"; then
    printf '%s\n' "$dynamic_shift_relocations" >&2
    echo "LLVM-generated Rust static-pointer object is missing its pointer-address relocation" >&2
    exit 1
fi
large_mem_relocations=$("$spu_readelf" -r "$tmp/dynamic_shift_large.o")
for relocation in R_SPU_ADDR16_HI R_SPU_ADDR16_LO R_SPU_ADDR32; do
    if ! grep -Fq "$relocation" <<<"$large_mem_relocations"; then
        printf '%s\n' "$large_mem_relocations" >&2
        echo "LLVM large-memory object is missing $relocation" >&2
        exit 1
    fi
done

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
    "$tmp/i64_compare_bridge.o" "$tmp/narrow_memory_bridge.o" \
    "$tmp/scalar.o" "$tmp/optimized_loop.o" "$tmp/stack_args.o" \
    "$tmp/dynamic_shift.o"

cat >"$tmp/vector_abi_start.s" <<'ASM'
.text
.p2align 3
.globl _start
.type _start,@function
_start:
  ilhu $1,3
  lnop
  iohl $1,0xffe0
  lnop
  brsl $lr,cellspu_vector_abi_test
  lnop
  wrch $ch28,$3
  lnop
  brsl $lr,cellspu_vector_stack_test
  lnop
  wrch $ch28,$3
  lnop
  stop 0
.size _start,.-_start
ASM
"$spu_as" -o "$tmp/vector_abi_start.o" "$tmp/vector_abi_start.s"
"$spu_ld" -Ttext=0 -e _start -o "$tmp/vector_abi.elf" \
    "$tmp/vector_abi_start.o" "$tmp/vector_abi_bridge.o" \
    "$tmp/vector_stack_bridge.o" \
    "$tmp/vector_abi.o"

cat >"$tmp/integer_division_start.s" <<'ASM'
.text
.p2align 3
.globl _start
.type _start,@function
_start:
  ilhu $1,3
  lnop
  iohl $1,0xffe0
  lnop
  brsl $lr,cellspu_integer_division_test
  lnop
  wrch $ch28,$3
  lnop
  stop 0
.size _start,.-_start
ASM
"$spu_as" -o "$tmp/integer_division_start.o" \
    "$tmp/integer_division_start.s"
libgcc=$("$spu_cc" -print-libgcc-file-name)
"$spu_ld" -Ttext=0 -e _start -o "$tmp/integer_division.elf" \
    "$tmp/integer_division_start.o" "$tmp/integer_division_bridge.o" \
    "$tmp/integer_division_short.o" "$libgcc"
"$spu_ld" -Ttext=0 -e _start -o "$tmp/integer_division_absolute.elf" \
    "$tmp/integer_division_start.o" "$tmp/integer_division_bridge.o" \
    "$tmp/integer_division.o" "$libgcc"

cat >"$tmp/start_large_mem.s" <<'ASM'
.text
.p2align 3
.globl _start
.type _start,@function
_start:
  ilhu $1, 3
  iohl $1, 0xf000
  brsl $lr, read_spu_reloc_pointer
  wrch $ch28, $3
  stop 0
ASM
"$spu_as" -o "$tmp/start_large_mem.o" "$tmp/start_large_mem.s"
"$spu_ld" --section-start=.rodata=0x10010 -e _start \
    -o "$tmp/large_mem.elf" "$tmp/start_large_mem.o" \
    "$tmp/dynamic_shift_large.o"
large_mem_symbols=$("$spu_readelf" -s "$tmp/large_mem.elf")
if ! grep -Eq '00010010[[:space:]].*SPU_RELOC_POINTER' \
        <<<"$large_mem_symbols"; then
    printf '%s\n' "$large_mem_symbols" >&2
    echo "large-memory fixture did not place its static pointer above 64 KiB" >&2
    exit 1
fi
large_mem_disassembly=$("$spu_objdump" -d "$tmp/large_mem.elf")
if [[ "$large_mem_disassembly" != *'ilhu'*',1'* || \
      "$large_mem_disassembly" != *'iohl'*',16'* ]]; then
    printf '%s\n' "$large_mem_disassembly" >&2
    echo "large-memory linked address did not resolve its high and low halves" >&2
    exit 1
fi

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

if ! (cd "$tmp" && ANERG_MBOX="$tmp/large_mem_mailbox" \
      timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" \
      "$tmp/large_mem.elf") >"$tmp/large_mem_emulator.log" 2>&1; then
    cat "$tmp/large_mem_emulator.log" >&2
    echo "LLVM large-memory SPU image failed or timed out in the emulator" >&2
    exit 1
fi
if ! grep -Fq '####### stop instruction reached:' \
        "$tmp/large_mem_emulator.log"; then
    cat "$tmp/large_mem_emulator.log" >&2
    echo "LLVM large-memory SPU image did not reach stop" >&2
    exit 1
fi
large_mem_bytes=$(wc -c <"$tmp/large_mem_mailbox")
large_mem_actual=$(od -An -v -tx1 "$tmp/large_mem_mailbox" | \
    tr -d '[:space:]')
if [[ "$large_mem_bytes" != 4 || "$large_mem_actual" != 5a17c0de ]]; then
    cat "$tmp/large_mem_emulator.log" >&2
    echo "expected large-memory pointer result 5a17c0de; got ${large_mem_actual:-<empty>} ($large_mem_bytes bytes)" >&2
    exit 1
fi

if ! (cd "$tmp" && ANERG_MBOX="$tmp/vector_abi_mailbox" \
      timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" \
      "$tmp/vector_abi.elf") >"$tmp/vector_abi_emulator.log" 2>&1; then
    cat "$tmp/vector_abi_emulator.log" >&2
    echo "SPU vector ABI image failed or timed out in the emulator" >&2
    exit 1
fi
if ! grep -Fq '####### stop instruction reached:' \
        "$tmp/vector_abi_emulator.log"; then
    cat "$tmp/vector_abi_emulator.log" >&2
    echo "SPU vector ABI image did not reach stop" >&2
    exit 1
fi
vector_abi_bytes=$(wc -c <"$tmp/vector_abi_mailbox")
vector_abi_actual=$(od -An -v -tx1 "$tmp/vector_abi_mailbox" | \
    tr -d '[:space:]')
if [[ "$vector_abi_bytes" != 8 || "$vector_abi_actual" != 0000000000000000 ]]; then
    echo "expected register and stack-passed GCC-to-Rust vector ABI results 0000000000000000; got ${vector_abi_actual:-<empty>} ($vector_abi_bytes bytes)" >&2
    exit 1
fi

if ! (cd "$tmp" && ANERG_MBOX="$tmp/integer_division_mailbox" \
      timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" \
      "$tmp/integer_division.elf") >"$tmp/integer_division_emulator.log" 2>&1; then
    cat "$tmp/integer_division_emulator.log" >&2
    echo "SPU integer division image failed or timed out in the emulator" >&2
    exit 1
fi
if ! grep -Fq '####### stop instruction reached:' \
        "$tmp/integer_division_emulator.log"; then
    cat "$tmp/integer_division_emulator.log" >&2
    echo "SPU integer division image did not reach stop" >&2
    exit 1
fi
integer_division_bytes=$(wc -c <"$tmp/integer_division_mailbox")
integer_division_actual=$(od -An -v -tx1 "$tmp/integer_division_mailbox" | \
    tr -d '[:space:]')
if [[ "$integer_division_bytes" != 4 || \
      "$integer_division_actual" != 00000000 ]]; then
    echo "expected signed and unsigned division/remainder checks to return 00000000; got ${integer_division_actual:-<empty>} ($integer_division_bytes bytes)" >&2
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
expected+=00055555
expected+=803768aaff80ffff807fff01133799aaffff807fffffff01ffff99aa
expected+=000037680012abfe13cdef240000cdef
expected+=008055aaf00f13cddca118efa1b2c3d4e5f60718
expected+=f60718ef249abcdee51188f01122334455667788
expected+=23456789cdf01123
expected+=5a17c0de
if [[ "$byte_count" != 464 || "$actual" != "$expected" ]]; then
    cat "$tmp/emulator.log" >&2
    echo "expected mailbox words $expected; got ${actual:-<empty>} ($byte_count bytes)" >&2
    exit 1
fi

printf 'LLVM 23.1.1 CellSPU scalar arithmetic and integer division, f32/f64 float codegen, vector C ABI, 64-bit comparisons, memory, relocation, and control flow: direct LLVM ELF32 EM_SPU objects; emulator returned 116 main results and checked vector ABI and division through 64 bits; GNU SPU assembler matched float encodings, which the emulator cannot execute\n'
