# Direct rustc to CellSPU probe

This experiment builds a minimal `#![no_core]` Rust arithmetic fixture with a
custom rustc built against this repository's LLVM 23.1.1 CellSPU target. Rustc
directly emits big-endian ELF32 `EM_SPU` objects. The fixture exercises `u32`
addition, `u64` addition/subtraction, 64-bit bitwise AND, constant and variable
`u64` left and logical-right shifts, signed `i64` arithmetic-right shifts, and
`u64` wrapping multiplication. The generated carry, borrow, mask, rotate,
quadword shift, and multiply encodings match GNU SPU binutils byte for byte.
GNU `spu-ld` links the objects with small SPU entry wrappers, and the pinned
emulator checks 88 arithmetic and shift results plus eight words from four
wrapping multiplication products before reaching `stop`. Variable shift tests
use counts 0, 1, 7, 8, 31, 32, 40, 63, 64, and 65,
covering byte boundaries and masked count behavior. The tests include negative
signed values, positive signed values, additional runtime `u64` inputs, and
constant shifts by 13.

A separate `#![no_core]` fixture compiles a dense ten-arm `u32` `match` to a
lookup table. The LLVM MC emitter encodes the unsigned immediate comparison,
indexed quadword load, and byte rotation used by that sequence; those
instructions match GNU SPU binutils. Its emulator image checks all ten arms
plus the fallback for 10 and `u32::MAX`, for twelve results. This covers one
optimized integer-match shape, not general switch or enum lowering.

A sparse `u32` match fixture covers a comparison tree combined with a compact
lookup table. It found a backend bug where LLVM's late branch folder could
lose the false edge after the target omitted an explicit branch to the
current layout successor. The target now preserves that destination through
CFG rewriting. Machine verification passes, generated compare and table
instruction encodings match GNU SPU binutils, and the emulator checks all
seven arms and five fallback inputs. This does not establish general switch,
enum, or control-flow support.

A raw-pointer fixture builds a local-store word address from a base pointer and
runtime index, then loads or stores through it. The generated `cwx`, `lqx`,
`rotqby`, `shufb`, and `stqx` encodings match GNU SPU binutils. The emulator
checks all eight array words before and after stores at indices 1, 4, and 7,
including neighbor preservation across 16-byte quadwords. These functions are
`unsafe`; this does not validate bounds, arbitrary pointer arithmetic, or
unaligned access.

The fixture uses Rust ABI because rustc 1.99.1 currently panics while lowering
`extern "C"` for the custom `arch = "spu"` target. The custom target JSON is
experimental and is not an in-tree rustc target. The source hand-defines only
the lang items needed for these arithmetic operations; this does not build
`core`, demonstrate ordinary `#![no_std]` support, validate the full Rust ABI,
or test a PPU loader. A separate Cargo `-Z build-std=core` probe reaches the
`core` crate but fails when rustc panics on the C ABI of `core::ffi::VaList`;
SPU foreign-ABI lowering must be integrated in rustc before `core` can build.
There is also a target-specific `VaList` layout requirement: the
[SPU ABI specification, version 1.9](https://www.ps3linux.net/ps3-filez/cellsdk-docs/3.1/standards/SPU_ABI-Specification_1.9.pdf)
defines `va_list` as a one-element array of a struct containing two pointers,
each aligned to 16 bytes. The installed SPU GCC confirms a 32-byte `va_list`.
Rust's generic fallback for the currently unrecognized `spu` architecture is
only one pointer, so building `core` correctly requires both foreign-ABI
classification and a matching target-specific `core::ffi::VaList` layout.

The rustc build also needs a narrow compatibility bridge: its LLVM build glue
expects PowerPC initializer names and a `powerpc` component for this target.
The custom CellSPU LLVM build exports those initializer aliases, while
`scripts/llvm-config-cellspu-rustc.sh` maps the requested component to
`cellspu`. These aliases only initialize CellSPU; they do not enable or emit
PowerPC code.

With the custom stage1 rustc, LLVM shared library, PS3 SPU binutils, and
`anergistic` emulator available, run:

```sh
RUSTC=/path/to/custom/stage1/bin/rustc \
CELLSPU_LLVM_LIBDIR=/path/to/llvm-build/lib \
SPU_AS=/path/to/spu-as \
SPU_LD=/path/to/spu-ld \
SPU_READELF=/path/to/spu-readelf \
SPU_OBJDUMP=/path/to/spu-objdump \
SPU_EMULATOR=/path/to/anergistic \
  scripts/test-rustc-cellspu.sh
```
