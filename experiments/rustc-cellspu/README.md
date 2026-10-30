# Direct rustc to CellSPU probe

This experiment builds a minimal `#![no_core]` Rust arithmetic fixture with a
custom rustc built against this repository's LLVM 23.1.1 CellSPU target. Rustc
directly emits big-endian ELF32 `EM_SPU` objects. The fixture exercises `u32`
addition, `u64` addition/subtraction, and 64-bit bitwise AND. The generated
`cg`, `addx`, `bg`, `sfx`, `and`, and `iohl` words match GNU SPU binutils byte
for byte. GNU `spu-ld` links the objects with a small SPU entry wrapper, and the
pinned emulator checks eight carry, borrow, high-word, and bitwise results
before reaching `stop`.

The fixture uses Rust ABI because rustc 1.99.1 currently panics while lowering
`extern "C"` for the custom `arch = "spu"` target. The custom target JSON is
experimental and is not an in-tree rustc target. The source hand-defines only
the lang items needed for these arithmetic operations; this does not build
`core`, demonstrate ordinary `#![no_std]` support, validate the full Rust ABI,
or test a PPU loader. A separate Cargo `-Z build-std=core` probe reaches the
`core` crate but fails when rustc panics on the C ABI of `core::ffi::VaList`;
SPU foreign-ABI lowering must be integrated in rustc before `core` can build.

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
