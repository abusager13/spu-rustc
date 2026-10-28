# Project goal: native Rust support for the PS3 Cell SPU

## Long-term outcome

Allow developers to write `#![no_std]` Rust programs that compile to native
Sony Cell SPU machine code, produce an SPU ELF image, load that image from a Rust
application running on the PS3 PPU, and execute it on the Cell processor.

## Acceptance criteria

- Use the SPU ISA, ABI, data layout, local-store address model, and executable
  format; keep them distinct from the PS3 PPU target.
- Build a real Rust compiler target, eventually including `core`, rather than
  relying on a host-target Rust compiler for general code generation.
- Provide Rust APIs for SPU SIMD, local-store access, DMA, mailboxes, and
  synchronization.
- Link and load SPU programs from Rust PPU code and validate execution in an
  SPU emulator or on PS3 hardware when available.
- Keep automated tests and document the toolchain, design choices, limitations,
  and untested behavior. Do not treat PPU simulation as SPU support.

## Current progress

The experimental `spu-rustc` driver compiles a restricted subset of straight-
line `#![no_std]` Rust scalar functions into big-endian ELF32 `EM_SPU` objects
and links either a stop-only `_start` or a scalar function plus minimal startup
into an `ET_EXEC` SPU image. Scalar startup can initialize up to 72 explicit
32-bit argument words in ABI registers. It uses host `rustc`
as a frontend, a small LLVM IR lowering pass, and the PS3 GNU SPU
assembler/linker. Tests cover add/subtract/bitwise operations, wrapping shifts,
all signed and unsigned integer comparison predicates returning `bool`,
constants, identity functions, multi-operation code, ABI argument placement,
liveness-based temporary reuse, and stop-only and scalar-entry ELFs. The scalar
startup initializes the local-store stack pointer, supplies optional
image-time argument words, calls the Rust function, posts its result to the
outbound mailbox, and stops. This is a tested
native-code milestone, not a general Rust target or PPU loader.

The current compiler/backend direction is to port and modernize LLVM's
historical CellSPU backend, using the PS3 GNU toolchain as the assembler,
linker, and ABI reference. See [the architecture investigation](docs/architecture.md)
and [the milestone plan](docs/roadmap.md).
