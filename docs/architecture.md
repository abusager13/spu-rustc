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

The user-supplied [`rust-ps3` project](https://github.com/ZephyrCodesStuff/rust-ps3)
is a useful PPU-side reference: it has a Rust PPU runtime, a PS3 target setup,
and direct LV2 syscall support. Its [README](https://github.com/ZephyrCodesStuff/rust-ps3/blob/main/README.md)
lists SPU tooling and inter-processor communication as future work. The current
[`syscalls.rs`](https://github.com/ZephyrCodesStuff/rust-ps3/blob/main/ps3/src/sys/syscalls.rs)
provides PPU thread, memory, file, and PRX calls, but no SPU thread-group/image
lifecycle wrapper.
It therefore does not supply the missing SPU compiler backend, SPU `core`
support, or a ready-to-use SPU loader. It remains a useful candidate PPU runtime
for a later launcher experiment. This repository has not copied its code; the
small loader here uses the locally available PSL1GHT APIs.

The normal Rust compiler delegates instruction selection, register allocation,
assembly/object emission, and much of ABI lowering to LLVM. A Rust target JSON
cannot add a CPU backend that LLVM does not contain. Stock LLVM 23.1.1, which
ships with this project's pinned rustc, does not register CellSPU; this
repository's separate C++ port adds an experimental `cellspu` target to a
custom LLVM build. A maintained `rustc --target=spu-sony-ps3` path still needs
that backend and a Rust target specification integrated together.

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
  for `i32`, `i64`, `f32`, and `f64`, and 16-byte slots for vectors. The
  installed GCC 9.5 SPU reference differs for scalar overflow arguments: its
  caller and callee code use 16-byte slots. See the
  [GCC SPU argument-lowering code](https://github.com/gcc-mirror/gcc/blob/releases/gcc-9.5.0/gcc/config/spu/spu.c#L3624-L3669).
  The maintained LLVM port follows the installed toolchain for scalar overflow
  slots. Its emulator check verifies the 73rd `u32` argument from a GCC caller
  into Rust code, and through a Rust-generated pass-through call. Other scalar
  widths, vectors, varargs, and full calling-convention compatibility remain
  unverified; the difference from the historical backend still needs review.
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
plugin stopped while loading that GCC 9.5 library. The default plugin build
first requires `gcc_jit_type_get_restrict`; building it without the `master`
feature then fails on the missing `gcc_jit_function_get_return_type` symbol.
Comparing the no-`master` `gccjit_sys` API against the GCC 9.5 library shows
44 required symbols are absent, so this is not a one-symbol compatibility
shim. No Rust code reached code generation. A follow-up inspection of the exact
GCC commit pinned by the local
`rustc_codegen_gcc` checkout (`e1c6e07b095d091177376a163da44039475e05e3`)
found `spu*-*-*` in GCC's unsupported-target list, and the commit does not
contain `gcc/config/spu/spu.md` or `spu.h` ([pinned `config.gcc`](https://github.com/rust-lang/gcc/blob/e1c6e07b095d091177376a163da44039475e05e3/gcc/config.gcc)).
That snapshot therefore cannot be configured for SPU by just building a
cross-`libgccjit`; it needs a restored or ported SPU backend. The installed PS3
GCC 9.5.0 is configured for SPU C and C++ with shared libraries disabled, so
it does not itself provide `libgccjit`. A
separate custom target JSON using `llvm-target: spu-unknown-none` also fails
with the stock rustc backend before code generation because LLVM 23 has no
registered SPU target. The pinned stable rustc 1.99.1 additionally requires
nightly `-Z unstable-options` to parse custom target JSON. A target JSON or a
cross-libgccjit object smoke alone therefore does not supply a Rust SPU target.

A separate legacy experiment did get two Rust functions through a Rust codegen
backend: nightly rustc 1.59 with `rustc_codegen_gcc` from 2021, GCC 9.5 SPU
`libgccjit`, temporary API compatibility edits, and no-op symbols for 33 newer
APIs unused by the tested functions. It emitted native SPU objects for a
`#![no_core]` identity function and a `u32` addition function that calls the
compiler's wrapping-add intrinsic. The addition object contains the native SPU
`a` instruction; both objects link and run in the emulator with the expected
mailbox results. A repeatable harness, samples, and custom target JSON now live
in `experiments/legacy-rustc/`. The JSON sets
`arch: "spu"`, which rustc exposes through `target_arch="spu"`, and uses the
historical CellSPU data layout. It retains a PowerPC LLVM triple as a
placeholder because stock LLVM has no SPU target. This is still not a
supported project build path: the adapter patches and compatibility shim are
temporary, other APIs and function forms remain untested, and it provides
neither a maintained Rust SPU target nor `core` support. Without the vector
compatibility implementation, the normal `#![no_std]` probe using
`u32::wrapping_add`
panicked on GCC JIT's `u8x2` type. A separate temporary vector-introspection
shim got past that point, but codegen then failed while lowering a core
aggregate constant with null GCC JIT values. Instrumentation traced the first
null value to GCC 9.5's missing `gcc_jit_context_new_array_constructor` API; the
temporary compatibility library returned null from its no-op stub, so byte
constants could not be represented. Cargo also reported that it could not find
target `compiler_builtins`. The old compiler rejects `extern "C"` for this
custom architecture. These results and the exact scope are recorded in
`docs/validation.md`.

There is no stock GCC release pairing in the checked versions that supplies
both sides of this experiment: the installed GCC 9.5 SPU backend predates the
libgccjit aggregate-constructor APIs, GCC 10.1's target configuration already
rejects `spu*-*-*`, and GCC 12 added the aggregate constructors and rvalue
global initialization that the Rust backend expects. The exact GCC 10.1
unsupported-target entry is in [`config.gcc`](https://github.com/gcc-mirror/gcc/blob/releases/gcc-10.1.0/gcc/config.gcc#L253-L291);
the API additions are listed in the [GCC 12 release notes](https://gcc.gnu.org/gcc-12/changes.html)
and declared in the [GCC 12 libgccjit header](https://github.com/gcc-mirror/gcc/blob/releases/gcc-12.1.0/gcc/jit/libgccjit.h#L867-L939).
This makes backporting the required libgccjit APIs to the SPU-capable GCC 9.5
build a concrete next experiment. It remains an untested direction: the
complete API surface needed to compile `core` must be established from actual
builds, and target `compiler_builtins` plus the Rust ABI still need support.

The GCC 9.5 SPU [machine description](https://github.com/gcc-mirror/gcc/blob/releases/gcc-9.5.0/gcc/config/spu/spu.md)
models the integer arithmetic pipe separately from `lnop`'s second pipe. Its
generated three-argument sum uses `lnop` between consecutive arithmetic
instructions and aligns functions to 8 bytes. The prototype follows those
observed scheduling and alignment conventions for its limited instruction set;
it does not yet implement a general SPU instruction scheduler.

## Long-term direction and feature layers

The foundational route toward an ordinary `rustc` target is to port and
maintain LLVM's historical CellSPU backend, then add a Rust target spec that
maps `spu-sony-ps3` to LLVM's `spu`/`cellspu` architecture. This reuses the
existing instruction descriptions, ABI rules, object support, and regression
tests while preserving Rust's parser, type checker, MIR, and `core` build
pipeline. The target, its data layout and ABI, native SPU ELF output, and a
verified PPU launch path come before target-specific safe libraries or task
runtimes. The initial target should use `panic=abort`; the historical backend
declares no exception support, so unwinding must remain unsupported until it
has a separately validated implementation.

### Compiler guarantees and hardware facts

Rust ownership, borrowing, and lifetimes can check relationships represented
in Rust types. They do not make the compiler aware of Cell hardware state, do
not automatically track an MFC transfer, and do not prove that a PPU effective
address is mapped or that a DMA request has completed. A safe API can provide
stronger guarantees only when its implementation correctly models these facts
and prevents callers from bypassing the model. Hardware facts that cannot be
established statically may require runtime checks or an explicit `unsafe`
operation.

In particular, local-store addresses and PPU effective addresses must remain
distinct concepts. A future safe DMA wrapper could own or borrow an aligned
buffer during a transfer, represent the in-flight state, and return access
only after completion is observed. These are design examples, not guarantees
provided by Rust or APIs implemented by the current prototype. Mailbox,
synchronization, and PPU–SPU communication wrappers need equivalent contracts
for ordering, ownership, and completion.

### Hardware APIs and higher-level programming

After the compiler and launch path pass their correctness gate, a target
library can add SIMD, local-store, DMA, mailbox, synchronization, and
PPU–SPU communication APIs. Its safe surface should encode the invariants the
library can enforce; explicit low-level interfaces should remain available
where developers need exact instructions, transfer timing, or resource control.
Higher-level buffer and task APIs may reduce manual transfer coordination, but
must compose with the lower-level interfaces rather than replace them.

A Cell-aware scheduler is a separate, optional runtime experiment. It may help
distribute suitable tasks across available SPUs, but it is not required for
native compilation or direct SPU execution. Its task placement, data movement,
and synchronization costs must be measurable and visible to users; programs
must retain a direct-control path.

### Performance and project scale

The goal is performance competitive with optimized C/C++ Cell toolchains, not
an assumption that Rust or abstraction layers are automatically free. Compare
representative workloads against the installed SPU GCC toolchain, inspect
generated instructions, and measure transfer and scheduling overhead before
making performance claims. Keep predictable-cost operations and low-level
escape hatches available. Large-project support also needs modular libraries,
reliable linking, diagnostics, tests, and debugging workflows; these should
grow after the compiler has a dependable ABI and object pipeline.

### Current implementation status

The current prototype deliberately does not try to masquerade as a general
backend. The GNU SPU toolchain remains the tested assembler/linker and ABI
reference. The legacy GCC adapter has a two-function experimental end-to-end
result, but still lacks a maintained Rust/GCC pairing, a supported target
specification, clean API compatibility, and full Rust ABI/data-layout
validation. The scalar translator remains a bounded validation harness, not
the primary compiler architecture.

The maintained port now lives in `backend/llvm/CellSPU/`, based on the
historical target source and licensed under its retained upstream NCSA
license. It builds the CellSPU code-generation library and an LLVM 23.1.1
`llc`. The pinned host rustc emits LLVM IR from a `#![no_std]` fixture; the
smoke harness replaces the host triple and data layout with CellSPU's
big-endian 32-bit-pointer values before custom `llc` lowers it. Add, subtract,
bitwise operations, increment, constant return, normalized equality, wrapping
`u32` multiplication, `swap_bytes`, `leading_zeros`, `trailing_zeros`,
`leading_ones`, `trailing_ones`, `count_ones`, both rotate directions, three immediate
`i32` shift forms, and variable shifts with an explicit five-bit mask pass
machine-instruction verification and emit ELF objects directly through LLVM.
GNU SPU binutils link them, and they run in the pinned emulator with the
expected results. The LLVM fixture tests
both emulator outcomes for all ten signed and unsigned `i32` and `i16`
comparison branches. A test-only GCC caller verifies signed and unsigned
`i16` max results across the C ABI.
Another GCC caller passes 73 `u32` arguments to Rust code, checking that the
first stack-passed value is read from the maintained 16-byte-slot ABI. The
fixture also checks a Rust function forwarding those 73 dynamic arguments and
a Rust function passing 72 zero constants plus `0x12345678` to a second Rust
function. All three paths return `0x12345678` in the emulator. This is a narrow
overflow argument check, not full ABI coverage.
Unsafe raw-pointer `u32` loads and stores also run against a local-store block;
the store test confirms that the other words in that quadword are preserved.
One stack-backed `u32` while loop also runs for inputs 0, 1, 5, and 10. A
separate `-O1` Rust loop with two loop-carried `phi` values and a helper call
returns the expected results for inputs 0, 1, 2, 5, and 10. This does not
provide `rustc --target=spu` or validate general pointer safety, pointer
arithmetic, cross-block accesses, other loop shapes, or general `phi`-node
lowering.
LLVM direct object emission now works for the instruction and relocation forms
covered by the smoke fixture. The maintained backend contains an experimental
MC code emitter, assembler backend, and ELF writer; GNU `spu-ld` still links
the resulting objects. This does not validate the full instruction encoder or
relocation set, and the emitter currently drops `HBRA` branch hints by writing
a no-op in the hint slot.
The triple patch marks CellSPU as big-endian, 32-bit ELF. The target still needs
ABI reconciliation, broader tests against SPU binutils, Rust target and `core`
integration, and resolution of its documented instruction-selection gaps. The installed GCC headers
`spu_intrinsics.h` and `spu_mfcio.h` are references for future interfaces, not
Rust APIs or evidence that their hardware contracts have been implemented.

## Prototype pipeline and ABI scope

The current driver:

1. Requires `#![no_std]` Rust source.
2. Uses host `rustc` to parse and type-check it and emit host LLVM IR.
3. Accepts one function with zero to 75 named 32-bit scalar or local-store
   address parameters: 72 register arguments plus up to three stack-passed
   arguments. More stack arguments are rejected. It supports a straight-line
   sequence of `add`, `sub`, wrapping `mul`, `and`, `or`, `xor`, `shl`, `lshr`,
   `ashr`, `rotate_left`, `rotate_right`, `leading_zeros`, `trailing_zeros`,
   `leading_ones`, `trailing_ones`, `count_ones`, `i32::wrapping_abs`, signed
   and unsigned `min`/`max`, unsigned `u32::saturating_add` and
   `u32::saturating_sub`, signed `i32::saturating_add` and
   `i32::saturating_sub`, `u32::reverse_bits`, `u32::swap_bytes`, scalar
   `select`, integer comparisons, and aligned `i32` loads and stores through a
   named local-store pointer parameter. It returns a parameter, computed
   `i32`, Rust `bool`, or a 32-bit literal.
   Add/subtract, logic, shift, and rotate
   immediates are used when the SPU encoding permits; multiply operands and
   other constants are materialized in a temporary register. `icmp` supports
   equality plus all signed and unsigned order predicates. Comparison masks
   become Rust bool's `0` or `1`. Rust unary `!` lowers to SPU `nor`, and
   `wrapping_neg` lowers to SPU `sfi`.
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
   Unsigned `u32::saturating_sub` accepts `llvm.usub.sat.i32`, compares before
   overwriting the left operand, then inverts the underflow mask to clear the
   result to zero. Signed `i32::saturating_add` and `saturating_sub` accept
   `llvm.sadd.sat.i32` and `llvm.ssub.sat.i32`; XOR/AND and `rotmai` detect
   overflow, then `selb` chooses `i32::MIN` or `i32::MAX`. These lowerings use
   temporary registers and have not been generalized to other widths.
   `reverse_bits` accepts `llvm.bitreverse.i32` and swaps adjacent bits, then
   2-bit groups, nibbles, and bytes using masks, shifts, and ORs before a final
   16-bit rotate. This implementation is limited to `i32`.
   `swap_bytes` accepts `llvm.bswap.i32` and exchanges adjacent bytes with a
   `0x00ff00ff` mask, shifts, and a final 16-bit rotate.
   `select i1` accepts an i1 condition and i32 arms and lowers to `selb`;
   comparison masks used by a select remain all-ones or all-zero. This only
   accepts straight-line `select` instructions and does not lower `br` or `phi`.
4. Assigns the first 72 parameters to C ABI registers `$3` through `$74` and
   loads up to three overflow parameters from 16-byte slots starting at
   `32($sp)` into `$75` through `$77`. It uses caller-saved
   registers `$3` through `$79` for computed values and reuses temporary
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
   32-bit argument words into `$3` through `$74`, and can place up to three
   additional words in 16-byte slots starting at `32($sp)`. It reserves the
   32-byte linkage area plus one 16-byte slot per overflow argument. It calls the
   function, posts its result to outbound mailbox channel 28, and stops.
   `--entry-args` supplies these image-time words. Both paths can invoke
   `spu-ld` to make an ELF executable.
   `--runtime-args` leaves incoming `$3` through `$6` intact and forwards them
   to a function with up to four 32-bit scalar or local-store address
   parameters. Its optional emulator test uses the emulator's `-r` register
   presets. The separate `--ppu-thread-args` startup shifts each of up to four
   incoming registers left by four bytes to extract the low 32 bits of the
   corresponding PSL1GHT `u64` thread argument, then calls a scalar Rust
   function. Emulator cases verify the extracted values for two and four
   arguments. This adapter follows PSL1GHT's documented SPU `main` arguments
   plus the installed SPU CRT/compiler ABI evidence; the actual PPU syscall to
   entry-register mapping has not been observed in a running thread. It does
   not pass PPU effective addresses for DMA.

The host LLVM data layout is ignored. These hand-coded ABI assumptions cover
only the accepted scalar `i32` operations, `i1` comparison results, and up to
three scalar stack arguments. The 16-byte overflow-slot spacing follows the
installed GCC 9.5 SPU code generator, checked with caller and callee examples.
Rust
wrapping shifts apply the LLVM-emitted `and 31` before shifting. SPU word
rotations use the low five bits of the count; variable right rotation negates
the count before `rot`, and immediate rotations use `roti`. Emulator checks
cover counts around the modulo-32 boundary, but this does not validate other
SPU rotate variants. The SPU's logical and arithmetic right-shift instructions
consume a negated count, so the lowering either negates a count at its last use
or reserves a temporary register when the value stays live. Comparisons
convert SPU's all-ones true mask into the C ABI's zero-extended Rust bool
value. The prototype only uses a pointer as the address for an aligned
local-store `i32` load or store. Store lowering uses
`lqd`/`cwd`/`shufb`/`stqd` to update one word while preserving its neighboring
words, and currently accepts a named `i32` value rather than a constant-only
store. It still rejects pointer arithmetic, other access widths, volatile and
atomic operations, control flow, other calls, other integer widths, most
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
channel 28, and stops. A third startup variant uses the PSL1GHT SPU thread-exit
sequence: it posts the result and executes `stop 0x102`.

The `ppu-loader/` prototype is a separate `#![no_std]` Rust PPU executable with
a small C bridge to PSL1GHT. It opens one SPU ELF, creates a one-thread group,
starts and joins it, retrieves the thread exit status, and returns that value.
The default image path is `/app_home/scalar.elf`; the PPU program can also use
an argv path followed by up to four decimal or `0x`-prefixed 64-bit values,
which it copies into PSL1GHT's `sysSpuThreadArgument` fields. Its ELFv1 PPU
executable cross-builds with nightly Rust and PSL1GHT, but has not been run in
RPCS3 or on hardware. A `--ppu-thread-args` adapter extracts the low 32-bit
word from up to four 64-bit incoming arguments and emulator tests exercise
those conversions, but this does not prove the PPU syscall's runtime
argument-to-register mapping. It does not map PPU effective addresses into SPU
local store or perform DMA. See
`docs/validation.md` for the build evidence and current boundaries.

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
