# Experimental Rust to Cell SPU compiler

This repository contains an early Rust-to-native-SPU compiler prototype. The
standing project goal and acceptance criteria are in [`GOAL.md`](GOAL.md). It
proves a narrow first milestone: compile simple `#![no_std]` Rust integer
functions into native SPU ELF objects.

The prototype uses `rustc` on the build host for Rust parsing and type checking,
lowers a small subset of its LLVM IR to SPU assembly, then invokes GNU `spu-as`
from the PS3 development toolchain. It does **not** add an official
`rustc --target=spu-sony-ps3` target or a general Rust backend. Its `--target`
flag names the prototype's output architecture.

Supported scalar functions have zero to 72 `i32` ABI parameters and straight-
line `i32` add, subtract, bitwise, and shift operations. Rust `wrapping_shl`
and `wrapping_shr` mask the shift count to five bits; signed right shifts use
arithmetic shift semantics. Equality and signed or unsigned integer
comparisons can return Rust `bool`, normalized to `0` or `1` in the SPU result
register. Functions may also return a parameter, an operation result, or any
32-bit literal. Immediate forms are used where supported and larger constants
are materialized in a register. The examples include scalar operations,
three- and eight-argument sums, shifts, and signed and unsigned comparisons.
A separate minimal `_start` example can be linked to an SPU ELF executable; it
immediately runs the native SPU `stop 0` instruction. See [`examples`](examples)
and the design notes in [`docs`](docs).

## Build and run

Requirements:

- Rust 1.99.1 (pinned in `rust-toolchain.toml`)
- The PS3 development toolchain's SPU binutils, including `spu-as` and
  `spu-objdump`

On Linux, the project has been validated with the `ps3dev/ps3toolchain`
`nightly-2026-10-11` x86_64 release. The bootstrap script downloads that
release, verifies its SHA-256, and extracts the SPU tools:

```sh
./scripts/install-spu-toolchain.sh "$HOME/opt"
export PATH="$HOME/opt/ps3dev/spu/bin:$PATH"
```

Build the compiler, run its unit and end-to-end tests, and compile the example:

```sh
SPU_REQUIRE_E2E=1 cargo test --offline
cargo run -- --target spu-sony-ps3 --emit=obj -o add_u32.o examples/add_u32.rs
spu-readelf -h add_u32.o
spu-objdump -dr add_u32.o
cargo run -- --target spu-sony-ps3 --emit=obj -o sum3_u32.o examples/sum3_u32.rs
spu-objdump -dr sum3_u32.o
cargo run -- --target spu-sony-ps3 --emit=elf -o stop.elf examples/stop_entry.rs
spu-readelf -h stop.elf
spu-objdump -d stop.elf
cargo run -- --target spu-sony-ps3 --emit=elf -o scalar.elf examples/scalar_entry.rs
spu-readelf -h scalar.elf
spu-objdump -d scalar.elf
```

The object is a relocatable ELF32 file with big-endian data and `Machine: SPU`.
The stop example links as a minimal ELF32 `EXEC` image. A scalar Rust function
can also link through the experimental startup, which sets the local-store
stack pointer, places up to 72 explicit 32-bit words in SPU ABI argument
registers, calls the function, writes its `u32` or normalized `bool` result to
the outbound mailbox, and stops. For example:

```sh
cargo run -- --target spu-sony-ps3 --emit=elf \
  --entry-args=0x1234,0x5678 -o add.elf examples/add_u32.rs
```

The argument words are constants embedded by startup; they are not supplied by
a PPU loader. The end-to-end tests check ELF headers and disassembled
instructions. `docs/validation.md` records the tested versions and evidence.

### Run the SPU emulator check

The optional emulator check uses the standalone `anergistic` SPU emulator. It
compiles and runs a Rust entry plus Rust arithmetic, bitwise, shift, and
comparison functions. Its startup loads fixed ABI argument words, including a
full-width constant; each result must be written to the outbound mailbox
before the emulator reaches `stop`.

```sh
git clone https://github.com/eth-man/ps3-cell-re-tools.git /tmp/ps3-cell-re-tools
git -C /tmp/ps3-cell-re-tools checkout 33251f85070744bb93615ea2069c15d0ec7fb796
make -C /tmp/ps3-cell-re-tools/anergistic anergistic
export PATH="$HOME/opt/ps3dev/ps3dev/spu/bin:$PATH"
SPU_EMULATOR=/tmp/ps3-cell-re-tools/anergistic/anergistic \
  scripts/test-spu-emulator.sh
```

The emulator is a separately downloaded GPLv2 project and is not included in
this GPL-3.0-only repository. This check validates the emitted instructions on
the exercised scalar path; it does not emulate the PS3 operating system, verify
DMA or multicore behavior, or replace testing on hardware.

To save generated assembly without assembling it:

```sh
cargo run -- --target spu-sony-ps3 --emit=asm -o add_u32.s examples/add_u32.rs
```

The frontend, assembler, and linker can be selected with `--rustc`,
`--assembler`, and `--linker`, or the `RUSTC`, `SPU_AS`, and `SPU_LD`
environment variables.

## Current limits

This is still a machine-code proof of concept, not a complete PS3 SPU
application toolchain. Its startup supports one scalar function per image,
with up to 72 image-time argument words, and returns one word through the
outbound mailbox; there is no Rust
PPU loader or general runtime. It has no `core` build, SIMD API, local-store
memory API, DMA, general mailbox API, or synchronization library. Hardware
execution has not been tested. Details and the remaining work are in
[`docs/architecture.md`](docs/architecture.md) and [`docs/roadmap.md`](docs/roadmap.md).

## License

This project is licensed under GNU GPL version 3 only; see [LICENSE](LICENSE).
