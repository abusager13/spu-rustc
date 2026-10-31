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
helper call, plus unsafe raw-pointer `u32` loads and stores and narrow scalar
memory operations:

1. The pinned host `rustc` emits host-target LLVM IR. The smoke harness replaces
   the host triple and data layout with `cellspu-unknown-elf` and the backend's
   big-endian 32-bit-pointer layout. The custom `llc` receives the explicit
   target triple and passes `-verify-machineinstrs` while directly writing
   ELF32 big-endian relocatable objects with machine `SPU`.
2. A small SPU entry wrapper and test-only C callers compiled by SPU GCC use
   the SPU C ABI; GNU `spu-ld` links the objects into an executable. GNU
   `spu-as` assembles the small entry wrapper.
3. The pinned `anergistic`
   emulator checks all 116 result words and reaches `stop`. In addition
   to signed and unsigned `i32` and `i16` branch cases, one mailbox word packs
   twenty `i64` equality, inequality, signed, and unsigned comparison results.
   Signed and unsigned `i64` cases include opposite high/low-word ordering to
   exercise full-width comparison. The
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
   four words to verify the other three were preserved. Narrow cases load
   signed and unsigned bytes and halfwords, including offsets at a 16-byte
   boundary. They store a byte while preserving its neighbors and load and
   store a packed halfword across a 16-byte boundary. The caller checks the
   changed bytes, and the packed load returns the stored halfword. The store
   calls also check that their stack spills do not overwrite caller state.
   Aligned `u64` loads and stores verify both halves and preserve neighboring
   bytes. Packed `u64` loads and stores at byte offset 13 cross a 16-byte
   boundary; both halves and the bytes around the access are checked. A GCC
   caller passes two `u64` arguments to a Rust function and verifies the
   64-bit return value, including the ABI path for the high and low words.
   A Rust static-pointer fixture emits `R_SPU_ADDR18` to locate the pointer and
   `R_SPU_ADDR32` for its initialized target address. Volatile byte reads
   follow the pointer, reassemble `0x5a17c0de`, and pass in the emulator.
   A separate `+large_mem` build emits `R_SPU_ADDR16_HI` and
   `R_SPU_ADDR16_LO`; its linker places the pointer at `0x10010`, and the
   emulator reads the same value after both halves are resolved.

An additional vector ABI image compiles one Rust `u32x4` addition to native
SPU `a`. A GCC C caller passes two four-lane vectors, checks all four returned
lanes, and reaches `stop` with a success result in the emulator. GNU
`spu-as` confirms the instruction encoding. A second GCC call passes 72 vectors
in registers and a 73rd on the stack; the Rust callee returns the last vector
and the caller checks every lane. The test enables Rust's internal `repr(simd)`
feature with `RUSTC_BOOTSTRAP=1` and retargets host Rust LLVM IR. It covers
these narrow `v4i32` cases, not a stable Rust SIMD API or general vector
support.

Integer division and remainder for signed and unsigned `i32` and `i64` use
LLVM runtime libcalls with SPU ABI names (`__divsi3`, `__udivsi3`, `__modsi3`,
`__umodsi3`, and their `di3` forms). In normal local-store mode, direct calls
to functions and runtime helpers use absolute `BRASL`/`R_SPU_ADDR16` by
default, which can address any instruction in the 256 KiB local store. The
optional `+short-calls` feature selects `BRSL`/`R_SPU_REL16`; the emulator
fixtures use it because the available emulator does not implement `BRASL`.
The SPU linker accepts an out-of-range `R_SPU_REL16` relocation and truncates
its displacement, so short calls are only valid when callers can guarantee
every target is within the signed 16-bit word range. The backend does not
create call veneers. `+large_mem` uses indirect address sequences instead.
The smoke test supplies 32-bit helper functions compiled by SPU GCC and links
the installed SPU `libgcc` for the 64-bit helpers; it checks the default
absolute objects and emulator results from the short-call object for all four
signedness/width combinations and both quotient and remainder. The test uses
Rust's unchecked division intrinsics to isolate backend codegen, so it does not
validate Rust's divide-by-zero or signed-overflow panic paths. GNU binutils
also confirm the absolute `BRASL` encoding and relocation for an ordinary
external declaration; that call is not executed in the emulator.

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

The same direct-rustc script also compiles a separate dense ten-arm `u32`
`match` fixture. Its `clgti`, `lqx`, and `rotqby` encodings match GNU SPU
binutils, and the emulator checks every arm plus two fallback inputs. This
validates one optimized lookup-table shape only.

A sparse `u32` match fixture also exercises a mixed comparison-tree and
compact lookup-table lowering. It exposed a branch-folding bug in which
`insertBranch` discarded an explicit false destination when that block was the
current layout successor. A later CFG rewrite could then lose that edge. The
backend now preserves explicit false targets until the final SPU branch
cleanup; the machine verifier passes, emitted compare and table encodings
match GNU binutils, and the emulator checks all seven arms plus five fallback
inputs. These fixtures cover two optimized integer-match shapes, not general
switch, enum, or arbitrary control-flow lowering.

A separate unsafe raw-pointer fixture computes `base + index * 4` and performs
dynamic `u32` loads and stores. It exercises `cwx`, `lqx`, `rotqby`, `shufb`,
and `stqx`; GNU SPU encodings match byte for byte, and the emulator checks all
eight words before and after stores at indices 1, 4, and 7. This covers one
aligned 32-byte array and verifies neighboring words are preserved. It does
not validate pointer bounds, arbitrary address calculations, or unaligned
access.

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
and two specific integer `match` shapes in `#![no_core]` fixtures with
hand-written minimal lang items. Multiplication is checked for four operand
pairs; this is not exhaustive arithmetic validation. Together, these paths do
not demonstrate ordinary `#![no_std]` code through rustc for SPU or a supported
`rustc --target=spu` workflow. This repository still has no maintained Rust
target specification integrated into the rustc source tree. A Cargo
`build-std` probe reaches `core`, then rustc panics while computing the C ABI
for `core::ffi::VaList` because `arch = "spu"` has no foreign-ABI lowering.
This project does not yet provide the rustc-side ABI support needed to build
`core` and target `compiler_builtins`. The `cellspu` LLVM
target is experimental; only the listed scalar operations, all signed and
unsigned `i32` and `i16` comparison branches, the listed `u32`, narrow, and
64-bit local-store pointer accesses, and the two loop fixtures have run in the
emulator. A
single count for each rotate direction, one byte-swap input, and only the
listed bit-count inputs are tested; this does not validate other rotate or
bit-count operations. A
test-only SPU GCC caller verifies signed and unsigned `i16` return values across
the C ABI. The stack-argument fixture checks the 73rd `u32` argument across GCC
and Rust caller/callee boundaries, including a Rust call whose arguments are
constants. The `u64` C ABI case covers one signature and one operand pair;
other 64-bit ABI combinations, varargs, and general ABI behavior remain
unvalidated. The vector C-ABI probe covers a `v4i32` addition and one 73rd
stack-passed `v4i32` argument/return; other vector widths, vector aggregates,
and additional stack layouts remain unvalidated. The optimized loop covers one
loop shape with two loop-carried values and an ordinary helper call; general loops, calls, and
`phi` lowering remain unvalidated. The raw-pointer functions are `unsafe`; no
pointer bounds, provenance, or ownership guarantee is added by this backend test. It
covers selected accesses in a 32-byte fixture, including packed halfword and
doubleword cases crossing a 16-byte boundary; this does not validate arbitrary
cross-block accesses, pointer arithmetic, or general memory semantics. Loops
with other control-flow shapes,
general merge/phi cases, and the rest of the ABI remain unvalidated here. The
direct-rustc match fixtures do not validate general switch or enum lowering.

LLVM now has an experimental MC code emitter, assembler backend, and ELF object
writer for the instruction and relocation forms exercised by the smoke check.
`llc -filetype=obj` directly emits the tested CellSPU objects, including
`R_SPU_ADDR16`, `R_SPU_ADDR16_HI`, `R_SPU_ADDR16_LO`, `R_SPU_ADDR18`,
`R_SPU_ADDR32`, and `R_SPU_REL16` relocations.
The object writer also maps `R_SPU_REL32`, but no LLVM-generated fixture
currently exercises it. This work does not implement or validate the full SPU
instruction encoder or relocation set. Absolute `BRASL` calls to both
defined functions and external symbols are encoded and checked against GNU
SPU binutils. The emulator executes optional short-relative-call fixtures,
but it does not execute absolute calls in this validation environment.
High/low symbol relocations are tested for the address sequence selected by
`+large_mem`, with the pointer linked at `0x10010`. This does not validate
arbitrary global addressing or all large-memory code paths.
The smoke script compares emitted `HBRA` branch hints against GNU SPU
disassembly. It validates the tested encoding, not the hints' performance
effect. Unsupported instruction forms can still fail object emission. The
tested variable shifts explicitly mask counts in Rust; this does not validate
other shift-count or overflow semantics. The smoke script also sends the tested
instruction streams through LLVM's assembly printer and GNU `spu-as`, then
compares disassembly after filtering LNOP filler slots. GNU SPU binutils remain
the linker and ABI reference. Do
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
   SPU binutils, including additional relocation types and object forms.
2. Add fixtures for more branch predicates, loop shapes, merge/phi cases,
   calls, ABI cases, and switch shapes, with disassembly and emulator checks.
3. Replace the minimal rustc initializer bridge with maintained target
   integration, then compile ordinary `#![no_std]` code and build and validate
   `core` and target support before claiming a usable Rust SPU target.
4. Test PPU loading and the real entry protocol separately from the current
   direct emulator wrapper.

The historical backend is a starting point for instruction and ABI behavior,
not evidence that all of its behavior is correct in this port.
