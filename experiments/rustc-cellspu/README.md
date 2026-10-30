# Direct rustc to CellSPU probe

This experiment builds one `#![no_core]` Rust `u32` addition function with a
custom rustc built against this repository's LLVM 23.1.1 CellSPU target. The
object is a big-endian ELF32 `EM_SPU` file and contains the native SPU `a`
instruction. GNU SPU binutils link it with a small entry wrapper; the pinned
SPU emulator checks that `20 + 22` reaches the outbound mailbox as `42` and
then reaches `stop`.

The function uses Rust's ABI because rustc 1.99.1 currently panics while
lowering `extern "C"` for the custom `arch = "spu"` target. The custom target
JSON is experimental and is not an in-tree rustc target. The source defines
only the lang items needed by this single operation. It does not build `core`,
does not demonstrate ordinary `#![no_std]` support, and does not validate the
full Rust ABI or a PPU loader.

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
