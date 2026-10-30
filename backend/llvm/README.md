# LLVM CellSPU backend port

`CellSPU/` is the start of the maintained native backend. Its source is based
on LLVM's pre-removal CellSPU target at commit
[`ac99eed043e84905bc2fb299ccaf5809e9c0e90f`](https://github.com/llvm-mirror/llvm/tree/ac99eed043e84905bc2fb299ccaf5809e9c0e90f/lib/Target/CellSPU)
and retains the upstream license in `LLVM-NCSA-LICENSE.txt`. The port targets
LLVM 23.1.1, matching the LLVM version bundled with this project's pinned
`rustc 1.99.1`.

This backend is written in C++ because LLVM's target-code-generation
interfaces are C++. It is compiler infrastructure behind the Rust frontend;
Rust programs and the Rust frontend remain Rust. The experimental translator
is still a separate validation harness and is not the long-term compiler path.

## Current status

The complete CellSPU code-generation library now builds against LLVM 23.1.1,
and the resulting `llc` registers the `cellspu` target. The backend has passed
a tested native-code path starting from `#![no_std]` Rust `i32` functions
covering addition, subtraction, AND, OR, XOR, increment, constant return,
equality with a normalized result, wrapping `u32` multiplication, and
immediate left, logical-right, and arithmetic-right shifts. An optimized
fixture also checks variable left, logical-right, and arithmetic-right shifts
after an explicit five-bit count mask, plus `leading_zeros`, `trailing_zeros`,
`leading_ones`, `trailing_ones`, `count_ones`, both rotate directions, and
`swap_bytes`. It also compiles ordinary
Rust conditionals
to SPU branches for all ten signed and unsigned `i32` and `i16` comparison
predicates. A stack-backed `u32` while loop
runs at `-O0`, including a loop backedge and stack frame. A separate Rust
`-O1` fixture checks a loop with loop-carried `phi` values and an in-loop
helper call, plus unsafe raw-pointer `u32` loads and stores:

1. The pinned host `rustc` emits host-target LLVM IR. The smoke harness replaces
   the host triple and data layout with `cellspu-unknown-elf` and the backend's
   big-endian 32-bit-pointer layout. The custom `llc` receives the explicit
   target triple and passes `-verify-machineinstrs` while directly writing
   ELF32 big-endian relocatable objects with machine `SPU`.
2. A small SPU entry wrapper and test-only C callers compiled by SPU GCC use
   the SPU C ABI; GNU `spu-ld` links the objects into an executable. GNU
   `spu-as` assembles the small entry wrapper.
3. The pinned `anergistic`
   emulator checks all ninety-one result words and reaches `stop`. The
   immediate shifts return `0x91a0`, `0x04000000`, and `0xffffffff`; the
   variable-shift cases verify counts 32, 33, and 36 are masked to five bits.
   Wrapping multiplication returns `0x369d0368` for `0x12345678 * 3` and
   `0xfffffffc` for `0xfffffffe * 2`. Leading-zero count returns 17 for
   `0x7fff` and 32 for zero; trailing-zero count returns 31 for
   `0x80000000`, 8 for `0x100`, and 32 for zero.
   Population count returns 13 for `0x12345678`, 32 for `0xffffffff`, and
   zero for zero.
   Leading-one count returns 8 for `0xff000000` and 32 for `0xffffffff`;
   trailing-one count returns 4 for `0xf` and 32 for `0xffffffff`.
   `rotate_left(0x12345678, 40)` and
   `rotate_right(0x12345678, 40)` return `0x34567812` and `0x78123456`.
   `swap_bytes(0x12345678)` returns `0x78563412`.
   Both
   outcomes of every signed and unsigned `i32` and `i16` comparison branch
   pass. The GCC caller widens signed and unsigned
   `i16` max results to `i32`, returning `5`/`7` and `0x5678`/`0x9876`. The
   stack-argument fixture checks the 73rd `u32` argument in a GCC-to-Rust call,
   a Rust-generated forwarding call, and a direct Rust call with constant
   arguments; each returns `0x12345678`.
   The `sum_to_n` loop returns `0`, `0`, `10`, and `45` for inputs `0`, `1`,
   `5`, and `10`. The optimized `sum_steps_opt` loop, which calls a no-inline helper
   that adds three, returns `0`, `3`, `7`, `25`, and `75` for inputs `0`, `1`,
   `2`, `5`, and `10`. Pointer cases load the first and fourth words of a 16-byte
   local-store block, store `0xaabbccdd` into its second word, then reload all
   four words to verify the other three were preserved.

In addition to the host-rustc-to-`llc` harness, a direct-rustc probe builds a
custom stage1 rustc against this target. It emits `EM_SPU` objects directly
from a minimal `#![no_core]` fixture with `u32` addition, `u64`
addition/subtraction, 64-bit bitwise AND, constant and variable `u64` left and
logical-right shifts, signed `i64` arithmetic-right shifts, and wrapping `u64`
multiplication. The generated carry, borrow, select-mask, rotate, quadword
shift, and multiply encodings match GNU SPU binutils byte for byte. A small SPU
entry wrapper exercises carry, borrow, high-word, bitwise, and left- and
right-shift results; all 88 mailbox values pass in the emulator. A separate
image exercises four 64-bit wrapping products and checks both words of each
result, for eight additional mailbox values.
Variable shift counts are 0, 1, 7, 8, 31, 32, 40, 63, 64, and 65. The test
also covers sign extension for negative values, positive signed values,
additional runtime `u64` inputs, and constant shifts by 13. The
probe uses an experimental custom target JSON, Rust ABI, and narrowly scoped
initializer/component aliases for rustc's build glue. It does not build or use
`core`, does not show ordinary `#![no_std]` support, and does not make this a
supported in-tree rustc target. Run it with
[`scripts/test-rustc-cellspu.sh`](../../scripts/test-rustc-cellspu.sh); setup
and exact constraints are recorded in
[`experiments/rustc-cellspu`](../../experiments/rustc-cellspu/README.md).

Run the smoke check with LLVM 23.1.1 `llc`, the PS3 SPU binutils, and the
standalone emulator available:

```sh
LLC=/path/to/llvm-build/bin/llc \
SPU_AS=/path/to/spu-as \
SPU_LD=/path/to/spu-ld \
SPU_CC=/path/to/spu-gcc \
SPU_READELF=/path/to/spu-readelf \
SPU_OBJDUMP=/path/to/spu-objdump \
SPU_EMULATOR=/path/to/anergistic \
  scripts/test-llvm-cellspu-backend.sh
```

To prepare the LLVM source tree, use the exact `llvmorg-23.1.1` commit
`6dfe1677ab8dffbc6ec13d53a1e0215d75147689` and run
[`scripts/test-llvm-cellspu-tablegen.sh`](../../scripts/test-llvm-cellspu-tablegen.sh)
with that source checkout and a build directory. The script applies the pinned
`cellspu` triple patch, adds the target to LLVM's target list, copies the
maintained sources, and generates the target descriptions. Build the compiler
with:

```sh
cmake --build /path/to/llvm-build --target llc -j6
```

## Current limits

The larger smoke check starts with Rust source, but invokes host `rustc` first
and then retargets its LLVM IR with a separate `llc` command. The direct-rustc
probe covers only the listed `u32` and `u64` arithmetic and shift operations
in `#![no_core]` fixtures with hand-written minimal lang items. Multiplication
is checked for four operand pairs; this is not exhaustive arithmetic
validation. Together, these paths do not demonstrate ordinary
`#![no_std]` code through rustc for SPU or a supported `rustc --target=spu`
workflow. This repository still has no
maintained Rust target specification integrated into the rustc source tree. A Cargo
`build-std` probe reaches `core`, then rustc panics while computing the C ABI
for `core::ffi::VaList` because `arch = "spu"` has no foreign-ABI lowering.
This project does not yet provide the rustc-side ABI support needed to build
`core` and target `compiler_builtins`. The `cellspu` LLVM
target is experimental; only the listed scalar operations, all signed and
unsigned `i32` and `i16` comparison
branches, aligned `u32` local-store
pointer loads/stores, and the two loop fixtures have run in the emulator. A
single count for each rotate direction, one byte-swap input, and only the
listed bit-count inputs are tested; this does not validate other rotate or
bit-count operations. A
test-only SPU GCC caller verifies signed and unsigned `i16` return values across
the C ABI. The stack-argument fixture checks the 73rd `u32` argument across GCC
and Rust caller/callee boundaries, including a Rust call whose arguments are
constants; other scalar widths, vectors, varargs, and general ABI behavior
remain unvalidated. The optimized loop covers one loop shape with two
loop-carried values and an ordinary helper call; general loops, calls, and
`phi` lowering remain unvalidated. The raw-pointer functions are `unsafe`; no
pointer bounds, provenance, or ownership guarantee is added by this backend test. It
covers one 16-byte block, not cross-block accesses, arbitrary pointer
arithmetic, or general memory semantics. Loops with other control-flow shapes,
general merge/phi cases, and the rest of the ABI remain unvalidated here.

LLVM now has an experimental MC code emitter, assembler backend, and ELF object
writer for the instruction and relocation forms exercised by the smoke check.
`llc -filetype=obj` directly emits the tested CellSPU objects, including
`R_SPU_ADDR16` and `R_SPU_REL16` relocations. This does not
implement or validate the full SPU instruction encoder or relocation set.
Branch-hint `HBRA` instructions currently occupy their instruction slot as an
SPU no-op, so branch prediction hints are dropped. Unsupported instruction
forms can still fail object emission. The tested variable shifts explicitly
mask counts in Rust; this does not validate other shift-count or overflow
semantics. The smoke script also sends the tested
instruction streams through LLVM's assembly printer and GNU `spu-as`, then
compares disassembly; the direct encodings match after excluding the deliberately
dropped branch hints. GNU SPU binutils remain the linker and ABI reference. Do
not treat the translator's larger emulator coverage as coverage of this LLVM
backend.

The initial port deliberately does not import the historical Cell SDK
intrinsic table. Ordinary Rust vector operations should lower through LLVM's
generic operations; target-specific intrinsics can be added with a maintained
Rust API and tests. The old `xshw` vector form is retained as an instruction
description but has no selection pattern until its packed-lane semantics are
specified and tested.

## Next backend work

1. Expand the MC emitter and relocation coverage and validate it against GNU
   SPU binutils, including branch hints and additional object forms.
2. Add fixtures for more branch predicates, loop shapes, merge/phi cases,
   calls, and ABI cases, with disassembly and emulator checks.
3. Replace the minimal rustc initializer bridge with maintained target
   integration, then compile ordinary `#![no_std]` code and build and validate
   `core` and target support before claiming a usable Rust SPU target.
4. Test PPU loading and the real entry protocol separately from the current
   direct emulator wrapper.

The historical backend is a starting point for instruction and ABI behavior,
not evidence that all of its behavior is correct in this port.
