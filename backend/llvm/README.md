# LLVM CellSPU backend port

`CellSPU/` is the start of the maintained native backend. Its source is based
on LLVM's pre-removal CellSPU target at commit
[`ac99eed043e84905bc2fb299ccaf5809e9c0e90f`](https://github.com/llvm-mirror/llvm/tree/ac99eed043e84905bc2fb299ccaf5809e9c0e90f/lib/Target/CellSPU)
and retains the upstream license in `LLVM-NCSA-LICENSE.txt`. The port targets
LLVM 23.1.1, matching the LLVM version bundled with this project's pinned
`rustc 1.99.1`.

## Current status

The backend's target descriptions now generate with LLVM 23.1.1's
`llvm-tblgen`. The reproducible check is:

```sh
scripts/test-llvm-cellspu-tablegen.sh /path/to/llvm-project
```

The source checkout must be at LLVM commit
`6dfe1677ab8dffbc6ec13d53a1e0215d75147689` (the `llvmorg-23.1.1` release).
The script applies the pinned `cellspu` triple patch, adds the target to
LLVM's build list, copies this maintained target source into that checkout,
configures a host build, and generates the target descriptions. The triple
patch identifies CellSPU as big-endian, 32-bit, and ELF.

This is not yet a working LLVM code generator. Compiling the C++ backend
currently fails against LLVM 23 APIs. Focused compilation now succeeds for
the target machine, subtarget, instruction information, register information,
frame lowering, and MC target-description translation units. The SelectionDAG
lowering and selector still have extensive API mismatches, and the historical
assembly printer has not been ported to LLVM's current MC printer interface.
There is no `llc` that emits SPU assembly, LLVM SPU object writer, or maintained
rustc target yet. The GNU SPU assembler remains the route for turning assembly
into native ELF after code generation works.

The initial port deliberately does not import the historical Cell SDK intrinsic
table. Ordinary Rust vector operations should lower through LLVM's generic
operations; target-specific intrinsics can be added with a maintained Rust
API and tests. The old `xshw` vector form is retained as an instruction
description but has no selection pattern until its packed-lane semantics are
specified and tested.

## Next backend work

1. Port SelectionDAG lowering and the assembly printer to LLVM 23 APIs.
2. Build and run the target pass pipeline, then compile scalar/control-flow IR
   to SPU assembly.
3. Assemble emitted code with the pinned GNU toolchain and check instructions,
   ABI behavior, and ELF metadata.
4. Add emulator tests before enabling a Rust target or building `core`.

The historical backend is a starting point for instruction and ABI behavior,
not evidence that the modern port has those guarantees.
