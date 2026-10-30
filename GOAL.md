# Project goal: native Rust support for the PS3 Cell SPU

## Long-term vision

Build and maintain a real Rust compiler target for the PlayStation 3 Cell SPU.
Developers should be able to write `#![no_std]` Rust, compile it to native SPU
machine code and an SPU ELF image, load it from a Rust application on the PPU,
and execute it on the Cell processor.

Over time, make substantial Cell software easier to write, safer to evolve, and
more productive to maintain than traditional C/C++ projects, without hiding
the hardware or sacrificing predictable low-level control. The compiler is the
foundation; libraries and optional runtimes come only after its ABI, code
generation, and execution model are reliable.

## Foundational compiler acceptance criteria

- Use the SPU ISA, ABI, data layout, local-store address model, and executable
  format; keep them distinct from the PS3 PPU target.
- Provide a maintained Rust target and native backend, including `core` for
  `#![no_std]` programs; host-target code generation remains a bounded
  validation technique only.
- Produce correctly linked SPU ELF images and load and execute them from a
  distinct PPU application. Validate the SPU path in an emulator and on
  hardware when available; a PPU simulation does not count as SPU execution.
- Test instruction selection, ABI and data layout, relocations, local-store
  boundaries, PPU-to-SPU arguments and results, and documented unsupported
  behavior. Keep the toolchain and reproducible validation steps documented.

## Later hardware-library objectives

After the compiler and execution path are established, provide Rust APIs for
SIMD, local-store memory, DMA, mailboxes, synchronization, and PPU–SPU
communication. Use ownership, borrowing, lifetimes, and types to encode the
rules a library can actually establish, such as buffer ownership while a DMA
transfer is in flight. Keep direct hardware access available through explicit
low-level interfaces.

Rust's type system does not automatically know Cell hardware state. Safe APIs
must be backed by correct implementations and documented contracts; facts that
cannot be proved statically may need runtime checks or an `unsafe` boundary.
Never claim that a wrapper makes DMA, aliasing, synchronization, or local-store
access safe without tests for those contracts.

## Later productivity and performance objectives

- Explore higher-level APIs that manage buffers, transfers, and SPU work while
  retaining a path to direct control.
- Investigate a Cell-aware task scheduler only as an optional runtime layer.
  It must not be required to compile or run SPU programs, and direct placement
  and synchronization must remain available.
- Aim for performance competitive with optimized C/C++ Cell toolchains. Check
  generated code and benchmark representative workloads before making
  performance claims; preserve predictable costs and escape hatches.
- Make large projects practical to build and maintain through modular APIs,
  reliable linking, useful diagnostics, testing, and debugging support.

These library and runtime objectives follow the foundational compiler gate;
they must not delay or weaken backend correctness.

## Current progress

The experimental `spu-rustc` driver compiles a restricted subset of straight-
line `#![no_std]` Rust scalar functions into big-endian ELF32 `EM_SPU` objects
and links either a stop-only `_start` or a scalar function plus minimal startup
into an `ET_EXEC` SPU image. Scalar startup can initialize up to 72 explicit
32-bit argument words in ABI registers. It uses host `rustc`
as a frontend, a small LLVM IR lowering pass, and the PS3 GNU SPU
assembler/linker. Tests cover add/subtract/bitwise operations, wrapping shifts,
all signed and unsigned integer comparison predicates returning `bool`,
wrapping `i32` multiplication via SPU halfword products, `u32` rotate-left and
rotate-right operations with variable or constant counts, `u32::leading_zeros`
via SPU `clz`, `u32::trailing_zeros` via compare/negate/and/`clz`, and
`u32::leading_ones`/`trailing_ones` via a complement and those count paths, and
`u32::count_ones` via `cntb`/`sumb`/`xshw`, plus signed `i32::wrapping_abs`,
signed and unsigned `min`/`max` via compare and select,
unsigned `u32::saturating_add` via a native sum, carry comparison, and overflow
mask, unsigned `u32::saturating_sub` via subtract/compare and inverted-mask
underflow clearing, signed `i32::saturating_add` and `saturating_sub` via
overflow masks and signed-limit selection, `u32::reverse_bits` via masked word
swaps and rotate, `u32::swap_bytes` via a mask, shifts, and rotate, and scalar
conditional selection through LLVM `select`, constants, identity functions,
multi-operation code, ABI argument placement,
liveness-based temporary reuse, and stop-only and scalar-entry ELFs. The scalar
startup initializes the local-store stack pointer, supplies optional
image-time argument words, calls the Rust function, posts its result to the
outbound mailbox, and stops. Local-store access now reads and writes aligned
`u32` words through 32-bit local-store pointers. Emulator checks exercise loads
and stores at all four word offsets in a quadword and verify that stores leave
neighboring words unchanged. A minimal Rust PPU launcher also cross-builds,
but has not been run in a PS3 emulator or on hardware. Its SPU startup adapter
for four 64-bit thread arguments passes emulator tests using seeded registers;
the PPU-to-SPU runtime mapping is still unverified. The translator is a
temporary validation harness for ABI and instruction cases, not the planned
primary compiler.

A separate legacy experiment now has a versioned custom target JSON using the
historical CellSPU data layout and a repeatable emulator smoke harness. With
external Rust 1.59/GCC 9.5 backend artifacts, it compiles and runs two
`#![no_core]` Rust-ABI functions: an identity function and a `u32` addition
using a compiler intrinsic. The emitted addition object contains native SPU
`a`. It does not build `core` or provide a supported target; the complete
target and runtime acceptance criteria remain open.

The current compiler/backend direction is to port and modernize LLVM's
historical CellSPU backend, using the PS3 GNU toolchain as the assembler,
linker, and ABI reference. The target source now lives under
`backend/llvm/CellSPU/` and its TableGen descriptions generate against the
LLVM 23.1.1 release used by the pinned rustc. The complete code-generation
library and `llc` build, and the backend compiles a narrow Rust-generated
scalar subset directly to SPU ELF objects. GNU SPU binutils link it to an ELF32
big-endian `EM_SPU` executable. The pinned emulator checks 116
results, including wrapping `u32` multiplication, `swap_bytes`, `leading_zeros`,
`trailing_zeros`, `leading_ones`, `trailing_ones`, `count_ones`, both rotate
directions, and immediate and explicitly masked variable left,
logical-right, and arithmetic-right `i32` shifts,
both outcomes of all ten signed and unsigned `i32` and `i16` branches; twenty
equality, inequality, signed, and unsigned `i64` comparison cases; an
unoptimized `while` loop; an optimized loop with loop-carried `phi` values and
a helper call; 16-bit returns through a GCC ABI caller; and unsafe raw-pointer
`u32` local-store loads and stores, signed and unsigned byte and halfword
loads, a byte store, aligned and packed `u64` loads and stores, and packed
halfword and doubleword accesses that cross a 16-byte boundary. A Rust static
pointer is read through `R_SPU_ADDR18` and `R_SPU_ADDR32` relocations; a second
large-memory image tests `R_SPU_ADDR16_HI`/`LO` at linked address `0x10010`.
A GCC caller also passes two `u64` values to Rust and checks the returned sum. The 73rd
`u32` argument also passes through
GCC-to-Rust, Rust forwarding, and a Rust call with constant arguments. The smoke harness
replaces host IR's data layout and triple with the CellSPU values before `llc`;
this is not a maintained rustc target. LLVM's MC emitter, assembler backend,
and ELF writer cover only the tested instruction and relocation subset.
The translator remains a separate validation harness, not the primary
compiler. This is still host `rustc` LLVM IR retargeted with a custom `llc`,
not `rustc --target=spu`; SPU `core`, full ABI support, and broader LLVM object
emission remain future work. See
[the LLVM backend port](backend/llvm/README.md),
[the architecture investigation](docs/architecture.md), and
[the milestone plan](docs/roadmap.md).

A separate custom stage1 rustc now sends a minimal `#![no_core]` Rust fixture
directly through the maintained LLVM target to native SPU ELF. It covers `u32`
addition, `u64` addition/subtraction, 64-bit bitwise AND, constant and variable
`u64` left and logical-right shifts, signed `i64` arithmetic-right shifts, and
`u64` wrapping multiplication. GNU SPU binutils match the carry, borrow, logic,
immediate, shift, and multiply encodings. The arithmetic and shift image checks
88 results; a separate multiplication image checks four products (eight words)
in the emulator. The variable shifts test counts 0, 1, 7,
8, 31, 32, 40, 63, 64, and 65; constant shifts by 13 and multiple signed and
unsigned 64-bit input patterns are also covered. This remains a narrow
experiment using Rust ABI and an experimental target JSON. It does not build
`core`, support ordinary
`#![no_std]`, or provide an in-tree rustc target.
