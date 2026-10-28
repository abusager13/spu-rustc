# Roadmap

## Milestone 0: native object proof

Implemented and statically validated: compile restricted `#![no_std]` Rust
`u32` functions, including multi-operation three- and eight-argument sums, to
ELF32 big-endian `EM_SPU` objects using host `rustc`, the prototype lowering
pass, and PS3 GNU SPU binutils. End-to-end tests cover add, subtract, AND, OR,
XOR, signed 10-bit immediates, narrow and full-width constant returns through
`il`/`ilhu`/`iohl`, and identity functions. A separate Rust example links a
minimal `_start` image that immediately executes `stop 0`, validated as an
ELF32 `ET_EXEC` image. No SPU execution claim is made.

## Milestone 1: scalar lowering expansion

Implemented and validated with SPU binutils: signed and unsigned integer
comparisons for all LLVM `icmp` predicates, returned as zero-extended Rust
`bool`, plus `u32` wrapping left/right shifts and `i32` arithmetic right
shifts. Dynamic Rust wrapping shifts use a five-bit count mask; SPU `rotm` and
`rotma` receive the negated count required by their instruction semantics.
It also lowers Rust `rotate_left` and `rotate_right` through LLVM's funnel-shift
intrinsics to SPU `rot` and `roti`; this covers only the rotate form where both
funnel inputs are identical. Rotate counts wrap modulo 32. Unit tests cover
lowering, bool normalization, temporary reuse, and preserving a count that
remains live. Rust `leading_zeros` also maps to the native SPU `clz` instruction
when LLVM emits `ctlz.i32` with defined-zero semantics. End-to-end tests compile
Rust examples, assemble them, inspect ELF headers, and check disassembly.
Emulator tests check variable rotate counts 0, 1, 31, 32, 33, and
`0xffffffff`, constant rotations, and leading-zero results for zero and
representative bit patterns. Rust `count_ones` lowers `llvm.ctpop.i32` to
`cntb`, `sumb`, and `xshw`; its native object is assembled and inspected, and
emulator results cover zero, one, the high bit, mixed byte patterns, and all
ones when using an emulator build that implements `sumb`. See
`docs/validation.md` for the pinned emulator's `sumb` limitation.
Rust unary bitwise NOT lowers to `nor`, and `wrapping_neg` lowers the LLVM
`sub i32 0, value` form to SPU `sfi`; both have native-object and emulator
checks.
Rust `trailing_zeros` lowers the defined-zero `cttz.i32` form through a native
SPU compare/negate/and/`clz` sequence; zero is explicitly corrected to 32.
Emulator tests cover zero, low and high bits, and mixed patterns. Rust
`leading_ones` and `trailing_ones` compile to a bitwise complement followed by
the respective zero-count path, and their zero and boundary cases also pass in
the emulator. Signed `i32::wrapping_abs` lowers defined wrapping semantics
through a `rotmai` sign mask, XOR, and subtraction; emulator checks include
`i32::MIN` and both signed boundaries.
Signed and unsigned scalar `min`/`max` lower the host LLVM `smin`, `smax`,
`umin`, and `umax` intrinsics to SPU `cgt`/`clgt` comparison masks and `selb`.
The emulator checks signed ordering across zero, unsigned ordering across the
sign bit, negative operands, and equal values.
Unsigned `u32::saturating_add` lowers `llvm.uadd.sat.i32` to an SPU sum,
unsigned overflow comparison, and all-ones mask. Emulator cases cover overflow,
a non-overflowing result of `u32::MAX`, and ordinary addition.
Unsigned `u32::saturating_sub` lowers `llvm.usub.sat.i32` to an SPU subtract,
unsigned underflow comparison, and inverted-mask clearing to zero. Emulator cases
cover underflow from zero, exact subtraction, and ordinary subtraction across
the sign bit.
Signed `i32::saturating_add` and `saturating_sub` lower `llvm.sadd.sat.i32` and
`llvm.ssub.sat.i32` through sign-bit overflow masks and select the correct
`i32::MIN` or `i32::MAX` limit. Emulator cases cover both overflow directions
and ordinary boundary arithmetic.
Rust `u32::reverse_bits` lowers `llvm.bitreverse.i32` through four masked
word-swap stages and a 16-bit rotate. The object test checks the assembled
instruction sequence, and emulator cases check zero, both endpoint bits, a
mixed pattern, and all ones.
Rust `u32::swap_bytes` lowers `llvm.bswap.i32` using a byte-pair mask, shifts,
and a 16-bit rotate. The object test checks native assembly, and emulator cases
cover the low byte, a mixed pattern, and all ones.
Straight-line LLVM `select i1` with `i32` arms lowers to SPU `selb`. When an
`icmp` result feeds a select, the compare mask stays all-ones/all-zero; a
standalone returned Rust `bool` remains normalized to 0 or 1. This does not
add general LLVM branches, loops, or `phi`-node support. Emulator cases cover
both selected arms and both arms computing an arithmetic result.
Local-store access accepts aligned `u32` loads and stores through named
opaque-pointer parameters. Loads lower to `ori`, `lqd`, and `rotqby`; stores
lower to `lqd`, `cwd`, `shufb`, and `stqd`, following SPU GCC's sequence for
word addresses that may not be 16-byte aligned. The emulator preloads four
words and checks reads and writes at all four word offsets, including that
stores preserve neighboring words. Pointer arithmetic, other access widths,
and general memory semantics remain unsupported.

## Milestone 2: scalar entry image

Implemented as an experimental image builder: a Rust function returning `i32`
or `bool` can be linked with startup code into an SPU `ET_EXEC` image. Startup
sets `$1` to the 256 KiB local-store limit, clears `$2`, initializes up to 72
explicit 32-bit argument words in `$3` through `$74`, and supports up to three
additional stack-passed words in 16-byte slots starting at `32($sp)`. Startup
reserves the 32-byte linkage area plus one 16-byte slot per overflow argument.
It then calls the function, posts the result on outbound mailbox channel 28,
and executes `stop 0`. End-to-end tests inspect the ELF and disassembly; the
emulator executes the zero-argument startup, a register-argument addition, one
stack-passed argument, and three stack-passed arguments. More than three stack
arguments remain unsupported. `--runtime-args` now also preserves up to four
incoming 32-bit values in `$3` through `$6` and forwards them to the Rust
function; the emulator test seeds those registers directly. The separate
`--ppu-thread-args` startup extracts the low 32 bits from up to four incoming
64-bit argument registers; emulator cases verify that conversion, while the
actual PPU launch mapping remains unverified. The translator remains a narrow
validation harness, with the rustc backend as the primary compiler direction.

## Milestone 3: wrapping 32-bit multiplication

Implemented and validated for variable and constant operands. The backend
forms the low 32 bits from two cross-halfword `mpyh` products, one low-halfword
`mpyu` product, and two wrapping additions, following the sequence emitted by
the installed SPU GCC reference. Native object tests check the instruction
sequence; emulator tests cover full-width cross products, overflow, and a
constant multiplier. Signed and unsigned wrapping multiplication share the
same low-word result. This does not add general multiply-accumulate or vector
multiplication support.

## Milestone 4: minimal PPU launcher build

Added a `#![no_std]` Rust PPU entry point and a small PSL1GHT C bridge. The
launcher opens an SPU ELF, creates and starts a one-thread group, joins it, reads
the SPU thread exit status, and returns that status from the PPU application.
It uses `/app_home/scalar.elf` by default and accepts an optional image path.
The path can be followed by up to four decimal or hexadecimal 64-bit values,
which the Rust PPU entry copies into PSL1GHT's `sysSpuThreadArgument` structure.
This field-passing path is cross-built and parser-tested but has not been
observed by a running SPU entry point.
The corresponding SPU image must use the experimental `--thread-exit` startup.
The launcher cross-compiles and links as an ELFv1 PowerPC64 PPU executable with
the available nightly Rust PPU target and PSL1GHT. It has not been run in an
emulator or on PS3 hardware, so loading and exit-status behavior remain
unverified at runtime. A new experimental SPU startup mode,
`--ppu-thread-args`, extracts each low 32-bit word from up to four incoming
64-bit argument registers and passes those words to a scalar Rust function.
The adapter passes emulator checks with register presets, guided by PSL1GHT's
documented SPU `main` arguments and the installed SPU CRT/compiler ABI. The
actual PPU-launched register mapping and loader runtime remain unverified.

## Future milestones

5. Port and modernize LLVM's historical CellSPU backend, then integrate it
   with Rust's LLVM backend. A follow-up check found that the GCC snapshot
   pinned by the current `rustc_codegen_gcc` checkout has removed SPU support:
   `spu*-*-*` is in its unsupported-target list, and the SPU machine description
   is absent. An isolated legacy `rustc_codegen_gcc` experiment compiled and
   emulated two `#![no_core]` Rust-ABI functions through GCC 9.5 `libgccjit`:
   an identity function and a `u32` addition using a compiler intrinsic. The
   latter emits native SPU `a`. The route needed temporary API remapping, 33
   no-op compatibility symbols, and a custom JSON with `arch: "spu"` plus a PowerPC LLVM-triple
   placeholder. The custom JSON now uses the historical CellSPU data layout,
   and a repository harness compiles and emulates both functions. This proves
   one route to native Rust-generated SPU code, not a supported project target.
   A normal `#![no_std]` probe using `core` first panicked when vector type
   introspection returned null. A temporary vector-introspection shim got
   past that point, but codegen then failed while lowering a core byte-array
   constant: GCC 9.5 lacks `gcc_jit_context_new_array_constructor`, and the
   compatibility shim returned null for that API. Cargo also could not find
   target `compiler_builtins`. The old
   compiler rejects `extern "C"` for `arch: "spu"`. Advancing this route
   requires a maintained Rust/GCC pairing, clean API compatibility, vector and
   aggregate lowering, target runtime support, and full Rust ABI validation.
   The checked GCC versions do not offer an off-the-shelf pairing: GCC 9.5
   supplies the SPU backend but not the aggregate-constructor libgccjit APIs;
   GCC 10.1 rejects SPU, while GCC 12 adds those APIs. Backporting the required
   libgccjit functionality to GCC 9.5 is the next concrete experiment, subject
   to measuring the full API surface through a `core` build. Preserve
   historical LLVM tests as backend support grows.
6. Define and implement a Rust SPU target specification, full calling
   convention and data layout, relocations, stack frames, memory operations,
   and linker support; build `core` with `#![no_std]` and `panic=abort`.
7. Run the PPU launcher in RPCS3 and, when available, on PS3 hardware. Validate
   `--ppu-thread-args` against the actual entry ABI, check local-store
   boundaries, and transfer PPU effective addresses through DMA. Replace
   baked-in argument words and the single-word result with a tested
   PPU-supplied argument and result protocol.
8. Add target-specific Rust APIs for SIMD and the MFC DMA, mailbox, and
   synchronization operations. Keep unsafe hardware interfaces separate from
   portable `core` functionality.
9. Run the full target test suite in an SPU emulator and, when hardware is
   available, on an SPU loaded by a PPU program.

The LLVM backend, Rust SPU target and `core`, PPU loader runtime validation,
hardware APIs, and hardware execution milestones remain open. This scalar
prototype is not a rustc SPU target and does not provide the full runtime or
execution support needed by the long-term goal.
