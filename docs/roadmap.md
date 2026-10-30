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
add general control-flow support to the experimental translator. The separate
maintained LLVM backend now passes Rust-generated signed and unsigned `i32 >`
branches through `cgt`/`clgt` and `brnz`, stack-backed merges, and both emulator
outcomes. Signed and unsigned `i16 >` branches now use `cgth`/`clgth` and
`brhnz`; a GCC caller checks narrow returns across the C ABI. A stack-backed
Rust `u32` while loop now runs for inputs 0, 1, 5, and 10. See the LLVM backend
record below. Other loop shapes, branch predicates, and general `phi`-node
lowering remain unvalidated.
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

The following tracks are deliberately ordered. Implementation of safe APIs and
optional runtime features is deferred until the foundational compiler and
execution gate is passed.

### Track A: essential native compiler and execution

5. **Restore and modernize the LLVM CellSPU backend.** Port instruction
   selection, ABI lowering, register allocation support, MC assembly/object
   support, and target registration to a maintained LLVM. Preserve and run the
   historical CellSPU tests where applicable; add build coverage for all
   backend components. Resolve the historical backend's documented gaps and
   reconcile its calling convention with the maintained SPU GNU toolchain.
   The maintained port has started in `backend/llvm/CellSPU/`, pinned to LLVM
   23.1.1 to match the project's rustc. A repeatable test now generates its
   TableGen descriptions and adds the `cellspu` triple against that release.
   The full code-generation library and `llc` now build. The pinned host rustc
   emits LLVM IR from a `#![no_std]` fixture; the harness replaces the host
   triple and data layout with CellSPU's big-endian, 32-bit-pointer values
   before the custom `llc` compiles it. Machine verification passes. LLVM
   directly emits the tested ELF objects, and GNU SPU binutils link an
   ELF32 big-endian `EM_SPU` executable. The pinned emulator returns
   ninety-one expected mailbox words, including wrapping `u32` multiplication,
   `swap_bytes`, all four zero/one count methods, `count_ones`, both rotate directions, and
   immediate and explicitly
   masked variable left, logical-right, and arithmetic-right `i32` shifts;
   both outcomes of all ten signed and unsigned Rust `i32` and `i16` comparison
   branches; an unoptimized stack-backed loop; an optimized loop with
   loop-carried `phi` values and a helper call; narrow return values through a
   GCC ABI caller; and unsafe local-store pointer loads and stores that
   preserve adjacent words. A 73rd `u32` argument passes through GCC-to-Rust,
   Rust forwarding, and a Rust-generated call with constant arguments.
   This validates a narrow Rust-source-to-LLVM path, not a maintained
   `rustc --target=spu` route. LLVM directly emits ELF objects for the tested
   subset; the MC encoder and relocation support remain incomplete. See
   `backend/llvm/README.md` for the reproduction command and exact limits.

   A first direct-rustc integration proof now complements this harness: a
   custom stage1 rustc built against the CellSPU LLVM target compiles a minimal
   `#![no_core]` Rust `u32` addition directly to an ELF32 big-endian `EM_SPU`
   object. The object contains native `a $3,$4,$3`, and GNU SPU binutils plus
   the emulator verify that 20 + 22 returns 42 and reaches `stop`. This uses an
   experimental target JSON, Rust ABI, and narrow initializer aliases. It
   does not yet compile ordinary `#![no_std]` crates, build `core`, or provide
   an in-tree rustc target. See `experiments/rustc-cellspu/`.

6. **Prove target code generation and ELF correctness.** Define and test the
   `spu-sony-ps3` target contract: SPU ISA, triple, data layout, calling
   convention, address spaces, relocations, stack frames, memory operations,
   object format, and linker behavior. Compile representative scalar,
   vector, control-flow, and memory programs; inspect their instructions and
   ELF metadata with SPU binutils; run them in an SPU emulator. Keep PPU
   addresses distinct from local-store addresses.

7. **Integrate the maintained Rust target and build `core`.** Use Rust's
   backend path for general code generation rather than a host target. Build
   `core` and required target support for `#![no_std]` with an initial
   `panic=abort` policy. Test target features, compiler builtins, ABI lowering,
   linking, diagnostics, and unsupported-feature errors.

8. **Validate PPU loading and the complete execution protocol.** Replace
   prototype register seeding and fixed arguments/results with a documented
   PPU-supplied argument, image, and result protocol. Verify the real entry ABI,
   local-store setup and bounds, thread status, and error paths in an SPU
   emulator. Run on PS3 hardware when available. A PPU build or simulated PPU
   call by itself does not pass this gate. PPU-to-SPU DMA contracts and safe
   DMA APIs belong to Track B.

The compiler gate is complete only when a maintained Rust target builds
`#![no_std]` code, produces a correct SPU ELF, and that ELF is loaded and
executed through the PPU path with the protocol tested above.

### Track B: safe hardware libraries after the compiler gate

9. **Specify hardware contracts and address types.** Distinguish local-store
   addresses, PPU effective addresses, DMA buffers, and ordinary Rust memory.
   Document alignment, size, lifetime, aliasing, ordering, and completion
   requirements from the SPU hardware and runtime. Identify which properties
   are statically enforceable, which need runtime validation, and which require
   `unsafe`.

10. **Build layered hardware APIs.** Add tested Rust interfaces for SIMD,
   local-store access, DMA, mailboxes, synchronization, and PPU–SPU
   communication. Use ownership and state-bearing types only where the
   implementation can uphold their contracts, such as retaining buffer access
   until DMA completion. Preserve explicit low-level operations for direct
   hardware control. Do not attribute hardware guarantees to Rust's type
   system alone.

11. **Explore higher-level SPU programming.** Prototype abstractions for
   grouping work, staging buffers, and coordinating transfers so developers
   need not manually manage every step. Keep these abstractions optional,
   composable with the low-level APIs, and subject to correctness and overhead
   measurements.

### Track C: optional Cell-aware runtime research

12. **Evaluate automatic task scheduling as a separate runtime.** Identify
   workloads that benefit from distributing tasks across available SPUs and
   measure scheduling, synchronization, and data-movement costs. Preserve
   explicit placement and direct hardware control. The scheduler is not a
   prerequisite for the compiler, hardware APIs, or SPU ELF execution; do not
   promise automatic speedups without workload-specific results.

### Cross-cutting quality goals

Across all tracks, keep the toolchain reproducible, grow emulator tests before
claiming behavior, and use hardware tests when available. Compare generated
code and representative benchmarks against optimized SPU C/C++ builds before
claiming competitive performance. Add compile-fail tests for safe API
contracts, runtime tests for hardware behavior, and link/debug workflows that
scale to multi-module projects. Document limitations and untested behavior at
each stage.

## Investigated alternative

The pinned `rustc_codegen_gcc` snapshot has removed SPU support. A separate
legacy experiment compiled and emulated two `#![no_core]` Rust-ABI functions
through GCC 9.5 `libgccjit`; it required temporary API remapping, 33 no-op
compatibility symbols, and a custom JSON with a PowerPC LLVM-triple
placeholder. It does not build `core` or provide a supported target. A
`#![no_std]` probe then hit missing vector introspection, aggregate-constructor
support, and target `compiler_builtins`; the old compiler also rejects
`extern "C"` for this architecture. The checked GCC versions do not provide an
off-the-shelf pairing: GCC 9.5 has SPU support but lacks needed libgccjit APIs,
GCC 10.1 rejects SPU, and GCC 12 has the APIs but not the SPU backend. This
experiment remains evidence about compatibility limits, not the project's
primary architecture or a planned substitution for the LLVM backend. See
`docs/validation.md` for the reproduction details.

The LLVM backend, maintained Rust SPU target and `core`, and PPU loader/runtime
validation remain open foundational work. Safe hardware libraries,
higher-level programming APIs, optional scheduling, and competitive
performance evidence are later objectives, not current prototype capabilities.
