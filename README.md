# Experimental Rust to Cell SPU compiler

This repository contains an early Rust-to-native-SPU compiler prototype. The
standing project goal and acceptance criteria are in [`GOAL.md`](GOAL.md). It
proves a narrow first milestone: compile simple `#![no_std]` Rust integer
functions into native SPU ELF objects.

The `spu-rustc` driver is a temporary validation harness for SPU instruction,
ELF, and ABI experiments. The primary compiler path is a maintained rustc
backend and target; the harness will stay limited to small cases that help
validate that path.

The prototype uses `rustc` on the build host for Rust parsing and type checking,
lowers a small subset of its LLVM IR to SPU assembly, then invokes GNU `spu-as`
from the PS3 development toolchain. It does **not** add an official
`rustc --target=spu-sony-ps3` target or a general Rust backend. Its `--target`
flag names the prototype's output architecture.

The maintained LLVM target is being developed separately under
[`backend/llvm`](backend/llvm/README.md). Its C++ code implements LLVM's
CellSPU target interfaces, which are written in C++; rustc uses that layer for
instruction selection and object generation. It runs inside the compiler, while
the project's source language and frontend remain Rust. A smoke check starts
from `#![no_std]` Rust functions: host `rustc` emits LLVM IR, then the harness
replaces its host triple and data layout with the CellSPU big-endian, 32-bit
pointer values before custom `llc` directly emits SPU object files for the
tested subset. GNU `spu-ld` links the result, which the pinned emulator
executes. The fixture tests scalar operations, wrapping `u32` multiplication,
immediate `i32` shifts and variable shifts with an explicit five-bit count
mask, `rotate_left`, `rotate_right`, `swap_bytes`, `leading_zeros`,
`trailing_zeros`, `leading_ones`, `trailing_ones`, `count_ones`, signed and
unsigned `i32` and `i16` branches, unsafe raw pointer `u32` loads
and stores in local store, and a
separate optimized loop with loop-carried values and a call in its body. This
does not provide `rustc --target=spu` or build `core` for SPU.

A separate direct-rustc proof builds a custom stage1 compiler against this LLVM
target and compiles a minimal `#![no_core]` fixture straight to big-endian
`EM_SPU` objects. It exercises `u32` addition, `u64` addition/subtraction,
64-bit bitwise AND, constant and variable `u64` left and logical-right shifts,
signed `i64` arithmetic-right shifts, and `u64` wrapping multiplication.
GNU SPU binutils match the generated carry, borrow, logic, immediate, shift,
and multiply encodings. The arithmetic and shift image checks 88 results; a
separate multiplication image checks four products (eight words) in the
emulator. The products cover carry between partial products, wraparound, and
mixed high/low words. Variable shifts cover counts 0, 1, 7, 8, 31, 32, 40, 63,
64, and 65; constant shifts by 13 and multiple signed and unsigned 64-bit input
patterns are also exercised. This uses an experimental target JSON and a
narrow LLVM initializer bridge. It does not demonstrate ordinary
`#![no_std]`, a build of `core`, or a supported rustc target. See
[`experiments/rustc-cellspu`](experiments/rustc-cellspu/README.md) for the
reproduction steps and limits.

Supported scalar functions have zero to 75 32-bit ABI parameters: integer
values or pointers interpreted as 32-bit local-store addresses, with 72
register-passed parameters and up to three stack-passed arguments. They support
straight-line `i32` add, subtract, wrapping multiply, bitwise operations
(including unary `!`), wrapping negation, shifts, and rotates,
`leading_zeros`, `trailing_zeros`, `leading_ones`, `trailing_ones`, and
`count_ones` operations, scalar conditional `select`, unsigned
`u32::saturating_add` and `u32::saturating_sub`, signed and unsigned `min`/`max`,
signed `i32::saturating_add` and `i32::saturating_sub`, signed
`i32::wrapping_abs`, `u32::reverse_bits`, and `u32::swap_bytes`. Rust
`wrapping_shl` and
`wrapping_shr` mask the shift count to five bits; signed right shifts use
arithmetic semantics.
`rotate_left` and `rotate_right` use the SPU rotate instructions and wrap
counts modulo 32. `leading_zeros` uses SPU `clz`, including a result of 32 for
zero. `trailing_zeros` expands the defined-zero LLVM intrinsic into SPU compare,
negate, bitwise-and, and `clz` instructions, returning 32 for zero.
`leading_ones` and `trailing_ones` count through a bitwise complement before
using the leading- or trailing-zero sequence. `count_ones` uses SPU `cntb`,
`sumb`, and `xshw` instructions.
The experimental translator's memory support is limited to aligned
`*const u32` and `*mut u32` parameters that read and write local-store words.
Loads use `lqd` and `rotqby`; stores use `lqd`, `cwd`, `shufb`, and `stqd` to
replace one word while preserving the other bytes in its quadword. Its stores
currently require a named `i32` value; constant-only stores, pointer arithmetic,
other access widths, and other memory operations remain unsupported.
Separately, the maintained LLVM backend's smoke suite exercises Rust `u8`,
`i8`, `u16`, and `i16` loads, a `u8` store, and a packed `u16` load/store whose
field crosses a 16-byte boundary. Those cases check local-store bytes through a
GCC caller and the emulator; they do not establish general memory semantics.
`wrapping_abs` builds a sign mask with `rotmai`, then uses XOR and subtraction;
it preserves `i32::MIN` with wrapping semantics.
Signed and unsigned `min`/`max` use the corresponding SPU compare and `selb`
instructions to select a result.
`reverse_bits` lowers LLVM's `bitreverse.i32` through four masked word swaps
and a 16-bit rotate.
`swap_bytes` lowers `bswap.i32` through a byte mask, shifts, and a 16-bit
rotate.
Unsigned `saturating_add` detects a wrapped result with `clgt` and applies an
overflow mask with `or` to return `u32::MAX` on overflow. Unsigned
`saturating_sub` compares the operands and uses an inverted mask to clear an
underflowed result to zero without treating the SPU link register as a zero
register. Signed `i32::saturating_add` and `saturating_sub` detect overflow
with sign-bit masks and choose the signed limit with `selb`.
Equality and signed or unsigned comparisons can return Rust `bool`, normalized
to `0` or `1` in the SPU result register. Functions may also return a
parameter, an operation result, or any 32-bit literal. Immediate forms are
used where supported and larger constants are materialized in a register. The
examples include scalar operations, variable and constant multiplication and
rotations, leading/trailing zero and one counts, population counts, bit
reversal, byte swapping, wrapping absolute value, signed and unsigned min/max,
signed and unsigned saturating addition and subtraction, conditional
selection, three- and eight-argument sums, shifts, signed and unsigned
comparisons, and aligned local-store word loads and stores.
The experimental translator handles a Rust conditional expression only when
host `rustc` lowers it to straight-line LLVM `select`. Separately, the
maintained LLVM backend compiles all ten signed and unsigned `i32` and `i16`
comparison branch predicates to native SPU code, with both outcomes checked.
Its smoke fixture also checks twenty `i64` equality, inequality, signed, and
unsigned comparisons through the CellSPU backend.
A GCC-compiled caller also verifies signed and
unsigned 16-bit return values across the SPU C ABI. The LLVM memory smoke cases
check narrow scalar loads and stores, including a packed halfword crossing a
quadword boundary, through raw pointers. A separate `-O1` loop with loop-carried
`phi` values and a helper call is checked for inputs 0, 1, 2, 5, and 10. The
smoke check also verifies the 73rd `u32` argument from GCC into Rust, through a
Rust-generated forwarding call, and in a direct Rust call with constant
arguments. Other loop shapes, general pointer arithmetic, and general `phi`
lowering remain unvalidated. See
[`backend/llvm`](backend/llvm/README.md).
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
cargo run -- --target spu-sony-ps3 --emit=obj -o mul_u32.o examples/mul_u32.rs
spu-objdump -dr mul_u32.o
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
registers, and stores up to three additional words in 16-byte stack slots when
the function has more than 72 parameters. It calls the function, writes its `u32` or
normalized `bool` result to the outbound mailbox, and stops. For example:

```sh
cargo run -- --target spu-sony-ps3 --emit=elf \
  --entry-args=0x1234,0x5678 -o add.elf examples/add_u32.rs
```

The argument words are constants embedded by startup. `--runtime-args` instead
forwards up to four incoming 32-bit SPU ABI words from `$3` through `$6` to the
Rust function; the emulator check seeds those registers directly. The separate
`--ppu-thread-args` startup adapts up to four incoming 64-bit PSL1GHT thread
arguments to 32-bit Rust parameters by extracting each low word. Its register
and conversion sequence is checked in the emulator with distinct high and low
words, but the PPU loader has not run in RPCS3 or on hardware, so the actual
PSL1GHT-to-entry behavior remains unverified. This mode cannot pass PPU
effective addresses for DMA. The end-to-end tests check ELF headers and
disassembled instructions. `docs/validation.md` records tested versions and
evidence.

### Build the experimental PPU loader

A small Rust PPU application with a PSL1GHT C bridge can open one SPU ELF,
start one SPU thread, join it, and return the thread's exit status. It expects
the SPU image to use `--thread-exit` so the PS3 thread group sees the SPU
status. The loader defaults to `/app_home/scalar.elf`; an optional image path
can be followed by up to four decimal or `0x`-prefixed 64-bit thread argument
values, which it copies into `sysSpuThreadArgument`.
For example, a PPU launch can use
`spu-rustc-loader.elf /app_home/scalar.elf 0x1234 42` to set `arg0` and
`arg1`, leaving the other two fields zero.

For a scalar SPU entry that consumes these as low 32-bit values, build the
corresponding image with `--ppu-thread-args`:

```sh
cargo run -- --target spu-sony-ps3 --emit=elf --ppu-thread-args --thread-exit \
  -o sum4.elf examples/sum4_u32.rs
```

```sh
cargo run -- --target spu-sony-ps3 --emit=elf --thread-exit \
  -o scalar.elf examples/scalar_entry.rs
make -C ppu-loader PS3DEV=/path/to/ps3dev PSL1GHT=/path/to/psl1ght
```

This builds a big-endian PowerPC64 ELFv1 PPU executable. The argument parser
and cross-link are tested, but the executable has not been run in RPCS3 or on a
PS3. The SPU adapter is based on PSL1GHT's documented `main` arguments and the
installed SPU CRT/compiler ABI; emulator tests validate its instruction-level
low-word conversion. They do not verify that a PPU-launched thread presents
the arguments in those registers. The loader does not pass PPU effective
addresses for DMA. This remains separate from a Rust SPU target and general
runtime support.

### Run the SPU emulator check

The optional emulator check uses the standalone `anergistic` SPU emulator. It
compiles and runs a Rust entry plus arithmetic, bitwise, shift, rotate,
bit-count, bit-reversal, byte-swap, wrapping-absolute, signed and unsigned
min/max, signed and unsigned saturating addition and subtraction, comparison,
and conditional-selection functions. It checks variable rotate counts 0, 1,
31, 32, 33, and `0xffffffff`, constant rotations, and leading-zero results
for zero and
representative bit patterns. It checks trailing-zero results for zero, low and
high bits, and mixed patterns. Bit-reversal checks include both endpoint bits,
a mixed pattern, and all ones. Byte-swap checks include a low byte, a mixed
pattern, and all ones. The one-count checks include zero and all-ones
inputs. The wrapping-absolute checks include positive, negative, minimum, and
maximum `i32` values. Min/max checks cover signed and unsigned order across the
sign bit and equal operands. Saturating arithmetic checks cover overflow,
underflow, boundary results, and ordinary operations. Startup loads fixed ABI
argument words, including a full-width constant, and checks the 73rd
stack-passed argument plus a three-argument stack-slot case; each result must be
written to the outbound mailbox before the emulator reaches `stop`.
The script also checks runtime argument forwarding when
`SPU_EMULATOR_HAS_REG_PRESETS=1` is set for an emulator supporting `-r`.

```sh
git clone https://github.com/eth-man/ps3-cell-re-tools.git /tmp/ps3-cell-re-tools
git -C /tmp/ps3-cell-re-tools checkout 33251f85070744bb93615ea2069c15d0ec7fb796
make -C /tmp/ps3-cell-re-tools/anergistic anergistic
export PATH="$HOME/opt/ps3dev/ps3dev/spu/bin:$PATH"
SPU_EMULATOR_HAS_REG_PRESETS=1 \
SPU_EMULATOR=/tmp/ps3-cell-re-tools/anergistic/anergistic \
  scripts/test-spu-emulator.sh
```

The emulator is a separately downloaded GPLv2 project and is not included in
this GPL-3.0-only repository. This check validates the emitted instructions on
the exercised scalar path; it does not emulate the PS3 operating system, verify
DMA or multicore behavior, or replace testing on hardware.

The pinned `anergistic` commit has an unimplemented `sumb` instruction. The
script therefore skips `count_ones` execution unless
`SPU_EMULATOR_HAS_SUMB=1` is set for an emulator build that implements it. The
recorded count-ones emulator run used a local emulator build with `sumb`
implemented from the SPU ISA definition; the repository does not modify or
include that emulator.

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
with up to 75 image-time argument words (72 registers and three stack slots), and
returns one word through the outbound mailbox; more than three stack arguments
are unsupported. The experimental `--runtime-args` mode forwards at most four
incoming 32-bit argument registers. Its experimental `--ppu-thread-args`
startup extracts the low 32 bits of up to four incoming 64-bit PSL1GHT thread
arguments; its emulator cases pass, but the PPU-launched register mapping has
not been run. There is no SPU `core` build or SIMD API, and local-store access
is limited to direct aligned `u32` loads and
stores; DMA, general mailbox operations, and synchronization remain
unsupported.
Hardware execution has not been tested. Details and the remaining work are in
[`docs/architecture.md`](docs/architecture.md) and [`docs/roadmap.md`](docs/roadmap.md).

A separate experiment compiled and emulated two `#![no_core]` functions through
a legacy `rustc_codegen_gcc` adapter using temporary API compatibility shims:
an identity function and a `u32` addition using a compiler intrinsic. Its
custom target sets `arch: "spu"` (visible to Rust's `target_arch` cfg) but uses
a PowerPC LLVM triple as a placeholder. The route is not integrated into this
project and does not provide a supported Rust SPU target or `core`; see the
[`validation record`](docs/validation.md#validation-record) for the exact scope
and limitations. A repeatable harness and its experimental target JSON are in
[`experiments/legacy-rustc`](experiments/legacy-rustc/README.md); it requires
the external 2021 codegen backend and GCC 9.5 compatibility shim.

## License

This project is licensed under GNU GPL version 3 only; see [LICENSE](LICENSE).
