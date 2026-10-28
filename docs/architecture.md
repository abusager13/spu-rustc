# Architecture and backend investigation

## Existing Rust and LLVM support

The current Rust source tree contains a Tier 3
[`powerpc64-sony-ps3` target spec](https://github.com/rust-lang/rust/blob/master/compiler/rustc_target/src/spec/targets/powerpc64_sony_ps3.rs)
for the 64-bit PPU. Its target spec uses the `powerpc64-sony-ps3` LLVM
triple, 64-bit pointers, ELFv1 ABI, and PS3-specific linker arguments. The
SPU is a different 128-register, 128-bit SIMD processor with its own ISA, ABI,
32-bit address space for its 256 KiB local store, and ELF machine type. Copying
the PPU spec would produce the wrong code. The pinned `rustc 1.99.1` used here does not yet
list `powerpc64-sony-ps3` among its targets, which shows that a source-tree
target spec and a released compiler's target list can differ.

The normal Rust compiler delegates instruction selection, register allocation,
assembly/object emission, and much of ABI lowering to LLVM. A Rust target JSON
cannot add a CPU backend that LLVM does not contain. Current LLVM does not
register a CellSPU target, so a real `rustc --target=spu-sony-ps3` needs a
compiler backend before a Rust target spec can work.

LLVM's historical `CellSPU` backend was removed in November 2012 in
[`llvm-project` commit 950d870](https://github.com/llvm/llvm-project/commit/950d8703b1e79df72b8acda09421d1e0c9f262b8).
The [code before removal](https://github.com/llvm-mirror/llvm/tree/ac99eed043e84905bc2fb299ccaf5809e9c0e90f/lib/Target/CellSPU)
registered the `cellspu` LLVM architecture (with
`spu` as a triple alias), contained instruction selection, calling convention,
assembly emission and ELF target code, and included a sizable SPU codegen test
suite. Its own README describes the backend as alpha quality and lists
unfinished work such as i32 division, some i128 operations, vector comparisons,
and untested intrinsics. The removal commit does not state a specific reason.

That backend records several useful design constraints:

- Target triple spelling used in tests: `spu`; LLVM's architecture name:
  `cellspu`.
- Big-endian data and 32-bit pointers. Its historical data layout is
  `E-p:32:32:128-f64:64:128-f32:32:128-i64:32:128-i32:32:128-i16:16:128-i8:8:128-i1:8:128-a:0:128-v64:64:128-v128:128:128-s:128:128-n32:64`.
  Pointer ABI alignment is 32 bits with 128-bit preferred alignment; the
  stack and preferred scalar/vector alignments are 128 bits. `usize` and
  pointers are 32 bits.
- Scalar and vector arguments and results are assigned to SPU registers `$3`
  through `$74`; the first two `i32` C ABI arguments use `$3` and `$4`.
  When registers are exhausted, the historical convention uses 8-byte slots
  for `i32`, `i64`, `f32`, and `f64`, and 16-byte slots for vectors.
- `$0` is the link register (`$lr`), `$1` the stack pointer (`$sp`), and `$2`
  the environment pointer. The historical backend marks `$80` through `$127`
  callee-saved. The stack grows down and is 16-byte aligned.
- A scalar result is returned in `$3`; a function returns control with
  `bi $lr` (the same physical register as `$0`).
- The backend had no JIT support; code was emitted as native SPU instructions.

These are historical backend facts, not yet a complete modernized Rust target
spec. The data layout, aggregate rules, unwind behavior, TLS, atomics, and PS3
loader contract still need revalidation against the maintained PS3 toolchain.

## Available native SPU toolchain

The open-source [`ps3dev/ps3toolchain`](https://github.com/ps3dev/ps3toolchain)
project still builds SPU GNU binutils and GCC. Its
[SPU binutils script](https://github.com/ps3dev/ps3toolchain/blob/master/scripts/005-binutils-SPU.sh)
uses
GNU binutils 2.22 and target `spu`; the SPU compiler script uses GCC 9.5.0 and
newlib 1.20.0 ([compiler script](https://github.com/ps3dev/ps3toolchain/blob/master/scripts/006-gcc-newlib-SPU.sh)).
The repository publishes Linux binaries, so a native assembler
and object inspector are available without restoring LLVM first.

The maintained SPU GCC backend is therefore the best immediate assembler and
linker source. Directly routing current Rust LLVM IR through an old GCC target
is not already supported, however: the PS3 toolchain configures its SPU GCC for
C and C++, not Rust. A separate host-shared GCC 9.5 `libgccjit` build configured
for `--target=spu` did emit an ELF32 big-endian `EM_SPU` relocatable object from
a minimal C API smoke program. This proves cross-target object generation is
possible with that GCC backend; it does not integrate Rust.

A Rust-backend probe using nightly rustc 1.101.0 and the `rustc_codegen_gcc`
plugin stopped while loading that GCC 9.5 library: the plugin requires the
missing `gcc_jit_type_get_restrict` symbol. No Rust code reached code
generation. The installed PS3 GCC 9.5.0 is configured for SPU C and C++ with
shared libraries disabled, so it does not itself provide `libgccjit`. A
separate custom target JSON using `llvm-target: spu-unknown-none` also fails
with the stock rustc backend before code generation because LLVM 23 has no
registered SPU target. The pinned stable rustc 1.99.1 additionally requires
nightly `-Z unstable-options` to parse custom target JSON. A target JSON or a
cross-libgccjit object smoke alone therefore does not supply a Rust SPU target.

The GCC 9.5 SPU [machine description](https://github.com/gcc-mirror/gcc/blob/releases/gcc-9.5.0/gcc/config/spu/spu.md)
models the integer arithmetic pipe separately from `lnop`'s second pipe. Its
generated three-argument sum uses `lnop` between consecutive arithmetic
instructions and aligns functions to 8 bytes. The prototype follows those
observed scheduling and alignment conventions for its limited instruction set;
it does not yet implement a general SPU instruction scheduler.

## Provisional long-term direction

The strongest path toward an ordinary `rustc` target is to port and modernize
the historical CellSPU LLVM backend, then add a Rust target spec that maps
`spu-sony-ps3` to LLVM's `spu`/`cellspu` architecture. This reuses the existing
instruction descriptions, ABI rules, object support, and old regression tests
while preserving Rust's mature parser, type checker, MIR, and `core` build
pipeline. The 2012 backend is only a reference: it needs API porting, modern
LLVM integration, tests against current SPU binutils, and completion of its
documented gaps.

The current prototype deliberately does not try to masquerade as that backend.
The GNU SPU toolchain remains the tested assembler/linker and ABI oracle. A
Rust GCC adapter is a concrete follow-up option because the cross-libgccjit
object smoke succeeded, but it needs a newer or patched cross libgccjit that
matches the current Rust backend API, followed by Rust SPU ABI and data-layout
validation. The scalar prototype remains the only Rust-to-SPU path validated
end to end in this repository.

The target-specific Rust API will also need to distinguish local-store
addresses from PPU effective addresses for DMA. The available SPU GCC install
includes `spu_intrinsics.h` and `spu_mfcio.h` as references for the MFC,
mailbox, and SIMD interfaces; they are not Rust APIs in this prototype.
The old backend declares no exception support; a Rust target should initially
use `panic=abort` and must not claim unwinding support.

## Prototype pipeline and ABI scope

The current driver:

1. Requires `#![no_std]` Rust source.
2. Uses host `rustc` to parse and type-check it and emit host LLVM IR.
3. Accepts one function with zero to 72 named `i32` parameters, a straight-line
   sequence of `add`, `sub`, wrapping `mul`, `and`, `or`, `xor`, `shl`, `lshr`,
   `ashr`, `rotate_left`, `rotate_right`, `leading_zeros`, `trailing_zeros`,
   `leading_ones`, `trailing_ones`, `count_ones`, `i32::wrapping_abs`, signed
   and unsigned `min`/`max`, unsigned `u32::saturating_add`, scalar `select`, or
   integer comparisons. It returns a parameter, computed `i32`, Rust `bool`, or
   a 32-bit literal.
   Add/subtract, logic, shift, and rotate
   immediates are used when the SPU encoding permits; multiply operands and
   other constants are materialized in a temporary register. `icmp` supports
   equality plus all signed and unsigned order predicates. Comparison masks
   become Rust bool's `0` or `1`.
   Rotate lowering accepts LLVM `fshl`/`fshr` only when the first two inputs
   match, the form used by Rust's `rotate_left` and `rotate_right` methods.
   `leading_zeros` accepts `llvm.ctlz.i32` only when its zero-undef flag is
   false, then uses SPU `clz`. `trailing_zeros` accepts `llvm.cttz.i32` only
   with defined-zero semantics, then expands to `ceqi`, `sfi`, `and`, and
   `clz` instructions with a correction that makes zero return 32. `count_ones`
   accepts `llvm.ctpop.i32` and uses `cntb`, `sumb`, and `xshw`. The Rust
   `leading_ones` and `trailing_ones` methods compile to a bitwise complement
   followed by the corresponding defined-zero count intrinsic. `wrapping_abs`
   accepts only `llvm.abs.i32` with its poison flag false and uses `rotmai`,
   XOR, and subtraction to preserve the signed minimum value.
   Signed and unsigned `min`/`max` accept `llvm.smin.i32`, `llvm.smax.i32`,
   `llvm.umin.i32`, and `llvm.umax.i32`; they compare with `cgt` or `clgt`, then
   select the winning input with `selb`.
   Unsigned `u32::saturating_add` accepts `llvm.uadd.sat.i32`, adds into a
   temporary, compares the wrapped sum with an addend using `clgt`, and ORs the
   overflow mask into the returned value.
   `select i1` accepts an i1 condition and i32 arms and lowers to `selb`;
   comparison masks used by a select remain all-ones or all-zero. This only
   accepts straight-line `select` instructions and does not lower `br` or `phi`.
4. Assigns parameters to C ABI registers `$3` through `$74`, uses caller-saved
   registers `$3` through `$79` for computed values, and reuses temporary
   registers after each value's last use. It expands 32-bit multiplication
   into two cross-halfword `mpyh` products, one low-halfword `mpyu` product,
   and two wrapping additions. It places the result in `$3` (using `il` or
   `ilhu`/`iohl` for literal returns), aligns functions to 8 bytes, inserts
   `lnop` pipe-1 fillers between consecutive pipe-0 operations, emits
   the SPU return branch, and invokes GNU `spu-as`.
5. For a separate `void _start() -> !` Rust entry that contains the specific
   `core::arch::asm!("stop 0", options(noreturn, ...))` operation, emits `stop
   0`. It can also link a scalar Rust function with startup code that
   initializes `$sp` and `$2`, optionally materializes up to 72 explicit
   32-bit argument words into `$3` through `$74`, calls the function, posts its
   result to outbound mailbox channel 28, and stops. `--entry-args` supplies
   these image-time words. Both paths can invoke `spu-ld` to make an ELF
   executable.

The host LLVM data layout is ignored. This is valid only for the currently
accepted register-only `i32` operations and `i1` comparison results. Rust
wrapping shifts apply the LLVM-emitted `and 31` before shifting. SPU word
rotations use the low five bits of the count; variable right rotation negates
the count before `rot`, and immediate rotations use `roti`. Emulator checks
cover counts around the modulo-32 boundary, but this does not validate other
SPU rotate variants. The SPU's logical and arithmetic right-shift instructions
consume a negated count, so the lowering either negates a count at its last use
or reserves a temporary register when the value stays live. Comparisons
convert SPU's all-ones true mask into the C ABI's zero-extended Rust bool
value. The prototype rejects
pointers, loads, stores, control flow, other calls, other integer widths, most
constant-only binary operations, and additional functions. Straight-line
sequences reuse caller-saved temporary registers after their last use and are
rejected when simultaneously live values exceed the available registers. The
driver explicitly disables Rust overflow checks so unsigned addition has
wrapping semantics matching SPU's word-add instruction.

Assembly is generated by the compiler and not written by application authors.
The output is a big-endian ELF32 relocatable object with machine type `EM_SPU`.
Object emission has been checked using the PS3 toolchain's own assembler,
`spu-readelf`, and `spu-objdump`.

The separate Rust `_start` sample remains a termination stub that immediately
executes `stop 0`. A second path links a scalar Rust function with minimal
startup code that initializes the local-store stack pointer, supplies optional
image-time argument words, posts the function's return word to outbound mailbox
channel 28, and stops. Neither path initializes an SPE context on the PPU or
loads an image from a PPU program.

## Why not claim a full target yet?

The current pipeline proves Rust frontend integration and native SPU object
generation for a small, testable subset. It does not provide general LLVM
lowering, a standard Rust target, memory semantics, a runtime, general-purpose
final linking, or an execution path. A proper target will need a backend with
full instruction selection and ABI support. The historical LLVM backend is a
valuable reference and contains regression tests, but its age and known gaps
make a direct source copy insufficient. The test compiler uses LLVM 23.1.1,
while the SPU backend code was removed in 2012. The chosen long-term direction
is a modern port, with the GCC adapter reconsidered only if cross-target object
generation is demonstrated.
