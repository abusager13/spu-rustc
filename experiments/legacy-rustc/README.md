# Legacy rustc/GCC SPU backend experiment

This research harness reproduces one narrow result: nightly rustc 1.59, an
externally patched 2021 `rustc_codegen_gcc` backend, and GCC 9.5 SPU
`libgccjit` compile a `#![no_core]` Rust-ABI identity function to ELF32
big-endian `EM_SPU`, then the SPU emulator executes it and reports `42`.

This is not a supported Rust target or a build path for this repository. The
target JSON uses `arch: "spu"` and the historical CellSPU data layout, but its
`llvm-target` is the PowerPC placeholder `powerpc-unknown-none` because the
stock LLVM backend has no SPU target. The function uses the Rust ABI; rustc
1.59 rejects `extern "C"` for this custom architecture. The harness does not
build `core`, and the current backend still cannot compile the `core` probe.

The codegen backend, host-shared GCC 9.5 SPU `libgccjit`, GCC dependencies, and
compatibility shim are external prerequisites. The tested adapter needed
temporary API remapping plus no-op symbols for newer APIs unused by this
identity function. Those components are deliberately not bundled here. The
script accepts their paths through environment variables and verifies the
generated object, linked executable, emulator stop, and mailbox result.

With the legacy toolchain and PS3 SPU binutils on `PATH`, run:

```sh
CODEGEN_BACKEND=/path/to/librustc_codegen_gcc.so \
LD_PRELOAD=/path/to/libgccjit-compat-stubs.so \
LD_LIBRARY_PATH=/path/to/gcc-9.5-spu-jit-libraries \
SPU_EMULATOR=/path/to/anergistic \
scripts/test-legacy-rustc-backend.sh
```

`RUSTC_TOOLCHAIN` (when using rustup's `rustc` shim), `RUSTC` (to use a direct
compiler path), `SPU_AS`, `SPU_LD`, `SPU_READELF`, and `SPU_EMULATOR_TIMEOUT`
can override the script defaults. See the project
[validation record](../../docs/validation.md) and
[architecture investigation](../../docs/architecture.md) for the broader
backend status and unresolved `core`, ABI, and target integration work.
