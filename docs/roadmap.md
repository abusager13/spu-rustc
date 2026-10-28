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
Unit tests cover lowering, bool normalization, temporary reuse, and preserving
a count that remains live. End-to-end tests compile Rust examples, assemble
them, inspect ELF headers, and check disassembly. See `docs/validation.md`.

## Milestone 2: scalar entry image

Implemented as an experimental image builder: a Rust function returning `i32`
or `bool` can be linked with startup code into an SPU `ET_EXEC` image. Startup
sets `$1` to the 256 KiB local-store limit, clears `$2`, initializes up to 72
explicit 32-bit argument words in `$3` through `$74`, calls the function, posts
the result on outbound mailbox channel 28, and executes `stop 0`. End-to-end
tests inspect the ELF and disassembly; the emulator executes both the
zero-argument scalar startup and an argument-taking Rust addition image. The
argument words are baked into startup, so this is not yet a PPU loader or a
general runtime contract.

## Milestone 3: wrapping 32-bit multiplication

Implemented and validated for variable and constant operands. The backend
forms the low 32 bits from two cross-halfword `mpyh` products, one low-halfword
`mpyu` product, and two wrapping additions, following the sequence emitted by
the installed SPU GCC reference. Native object tests check the instruction
sequence; emulator tests cover full-width cross products, overflow, and a
constant multiplier. Signed and unsigned wrapping multiplication share the
same low-word result. This does not add general multiply-accumulate or vector
multiplication support.

## Future milestones

4. Port and modernize LLVM's historical CellSPU backend, then integrate it
   with Rust's LLVM backend. Revisit a GCC codegen adapter only if a concrete
   cross-`libgccjit` build proves it can create SPU objects. Preserve historical
   LLVM tests and add Rust ABI tests as backend support grows.
5. Define and implement a Rust SPU target specification, full calling
   convention and data layout, relocations, stack frames, memory operations,
   and linker support; build `core` with `#![no_std]` and `panic=abort`.
6. Implement a Rust PPU loader for SPU ELF images. Validate image loading,
   arguments, local-store boundaries, outbound mailbox reads, and PPU
   effective-address transfer through PSL1GHT or the PS3 SDK. Replace the
   current baked-in argument words and single-word result with a PPU-supplied
   argument and result protocol.
7. Add target-specific Rust APIs for SIMD and the MFC DMA, mailbox, and
   synchronization operations. Keep unsafe hardware interfaces separate from
   portable `core` functionality.
8. Run the full target test suite in an SPU emulator and, when hardware is
   available, on an SPU loaded by a PPU program.

The LLVM backend, Rust target and `core`, PPU loader, hardware APIs, and SPU
execution milestones remain open. This scalar prototype is not a rustc target
and does not provide the full runtime or execution support needed by the
long-term goal.
