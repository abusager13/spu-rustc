# Validation record

## Environment

- Rust host compiler: `rustc 1.99.1 (58cf8f9c3 2026-10-13)`
- Rust's LLVM version: 23.1.1
- PS3 SPU GNU toolchain release: `ps3dev/ps3toolchain` `nightly-2026-10-11`
- SPU assembler: GNU Binutils 2.22 (`spu-as`)
- SPU C compiler reference: GCC 9.5.0 (`spu-gcc`)

The toolchain was extracted under `/tmp/ps3dev` for this run. It is not vendored
in this repository.

## Checks performed

1. Assembled a generated-style SPU function with `spu-as`.
2. Inspected the output with `spu-readelf -h`: ELF32, big endian, relocatable,
   machine `SPU` (ELF machine id 23).
3. Disassembled with `spu-objdump -dr`: the object contains the expected SPU
   instruction and `bi $0` return.
4. Compiled reference C functions with `spu-gcc -O1 -S`; GCC emitted
   `a $3,$3,$4` followed by `bi $lr`, `ai $3,$3,1` for increment, and `andi`,
   `ori`, and `xori` for bitwise constants. The references are only for
   ABI/codegen comparison; the shipped examples are Rust.
5. Ran `SPU_REQUIRE_E2E=1 cargo test --offline` with the toolchain paths set:
   all 32 unit tests and all three end-to-end tests passed. One
   integration case compiled 32 `#![no_std]` Rust object examples, checked ELF
   machine ids, and checked disassembled instructions for arithmetic, bitwise
   operations, dynamic and immediate wrapping shifts, all ten signed/unsigned
   comparison predicates, bool normalization, arithmetic immediates, the
   three-argument sum, identity, and constant returns. The other two
   integration cases linked stop-only and scalar-entry Rust examples into SPU
   `ET_EXEC` images. The scalar-entry test also linked an argument-taking Rust
   addition as `ET_EXEC`, checking startup loads into `$3` and `$4`. Its
   disassembly contains stack initialization, a relocated `brsl` call,
   `wrch $ch28,$3`, `stop 0`, and the Rust function's return. The unit suite
   lowers a generated 100-operation IR chain with register reuse, preserves a
   shift count whose SSA value is still live, and rejects a function with too
   many simultaneously live values. ABI unit tests verify that argument 72
   maps to `$74` and reject a 73rd stack-passed argument.
6. Inspected the generated `sum3_u32` object. `spu-objdump -dr` showed:
   `a $6,$3,$4`, `lnop`, `a $3,$5,$6`, and `bi $0`, confirming argument
   placement, intermediate-register use, the pipe-1 filler between pipe-0
   operations, and final result placement in the emitted object. The source
   aligns generated functions to 8 bytes, matching GCC's SPU assembly output.
   The `sum8_u32` example additionally verifies that the liveness allocator
   reuses `$11` and `$12` across a longer eight-argument sum.
7. Compiled the same three-argument sum with `spu-gcc -O1 -S`; GCC used the
   expected `$3`, `$4`, and `$5` argument registers and returned through `$3`.
   Its register allocation differed, but the SPU ABI placement agreed.
8. Checked GCC's `il`/`ilhu`/`iohl` output and assembled the Rust narrow and
   wide constant-return examples. `spu-objdump` showed `il $3,42` paired with
   `bi $0`, and full-width materialization with `ilhu $3,4660`, `lnop`,
   `iohl $3,22136`, and `bi $0`.
9. The `add_large_constant` object disassembles to `il $4,4096`, `lnop`,
   `a $4,$3,$4`, `lnop`, `or $3,$4,$4`, and `bi $0`, confirming the large
   constant path and its pipe fillers.
10. The `add_wide_constant` integration case checks that `ilhu`/`iohl` load a
    full-width constant into a temporary register before the register add.
11. Linked a Rust `_start` example with `spu-ld`; `spu-readelf` reported ELF32,
   big endian, `EXEC`, machine `SPU`, and the integration test checked its
   program headers and `stop` instruction. The loadable segment starts at
   address 0, has execute/read flags, and is 16 bytes in this linker output.
   Also linked `examples/scalar_entry.rs` with generated startup; `spu-objdump`
   confirmed `$sp` initialization to `0x40000`, `$2` initialization, the call
   relocation, outbound-mailbox result write, stop, and the Rust function's
   `il $3,42`/`bi $0` body.
12. Confirmed the installed stable Rust compiler does not list
   `spu-sony-ps3` as a target (`rustc --print cfg --target spu-sony-ps3` reports
   that the target specification is missing). It also does not list the PPU
   target spec present in current Rust source.
13. Checked the available PS3 SPU GDB build recipe; it configures GDB with
   `--disable-sim`, so it could not provide execution validation.
14. Compiled C reference shift and comparison functions with `spu-gcc -O1 -S`.
   GCC masks wrapping shift counts with `andi ...,31`, negates right-shift
   counts with `sfi ...,0`, then uses `rotm` or `rotma`; it uses `shl` for a
   left shift, `cgt` for signed comparisons, and `clgt` for unsigned
   comparisons. The Rust-generated objects use the same count convention and
   compare instructions. SPU binutils assembled all generated functions, and
   `spu-objdump -dr` confirmed the expected instructions and 0/1 bool
   normalization.
15. Downloaded the documented toolchain release again and verified SHA-256
   `66afbfc725221d3a6f02f219a6ce47ee793ff6b0890f176a9d10d2c89c91dda5` before
   extracting the SPU binutils used for the new checks.
16. Built the standalone `anergistic` SPU emulator from
   [`eth-man/ps3-cell-re-tools`](https://github.com/eth-man/ps3-cell-re-tools)
   at commit `33251f85070744bb93615ea2069c15d0ec7fb796` (2026-09-09). It is a
   separate GPLv2 tool and is not included in this GPL-3.0-only repository.
17. Ran the generated `scalar_entry.elf`. The emulator executed the startup,
   Rust function, outbound-mailbox write, and `stop`; it exited 0 with `$3 =
   0x2a` and recorded mailbox bytes `00 00 00 2a`.
18. Compiled `examples/add_u32.rs` directly to an `ET_EXEC` image using
   `--entry-args=0x12345678,0x5678`. Generated startup materialized the
   full-width first word with `ilhu`/`iohl`, placed both values in `$3` and
   `$4`, called the Rust function, and sent its result to the mailbox. The
   emulator executed startup and Rust `a`/`bi`, exited 0 with `$3 = 0x1234acf0`,
   and recorded mailbox bytes `12 34 ac f0`.
19. Extended the emulator check to execute Rust subtraction, AND, OR, XOR,
   wrapping left shift, logical right shift, arithmetic right shift, equality,
   inequality, signed greater-than, and unsigned greater-than. The emulator
   produced the expected mailbox words for all cases, including a shift count
   of 32 (masked to zero), a logical shift count of 33 (masked to one), and
   distinct signed/unsigned comparisons across the sign bit. The repeatable
   `scripts/test-spu-emulator.sh` checks every mailbox value and confirms each
   image reaches `stop`.
20. Compiled variable `u32` and `i32` plus constant `u32` wrapping
   multiplication as native SPU ELF. The generated sequence uses `mpyh` for
   both cross-halfword products, `mpyu` for the low-halfword product, and two
   word additions; it matches the instruction sequence produced by
   `spu-gcc -O1` for a C reference multiply. `SPU_REQUIRE_E2E=1 cargo test
   --offline` passed all 35 unit tests and all three end-to-end tests,
   including ELF and disassembly checks for both multiplication forms. The
   emulator returned `0x00000001` for `0xffffffff * 0xffffffff`,
   `0x242d2080` for `0x12345678 * 0x9abcdef0`, `0xfffffff2` for signed
   `-2 * 7`, and `0xe242d208` for `0x89abcdef * 0x12345678`; each image
   reached `stop` and wrote the expected outbound mailbox word.
21. Added `rotate_left` and `rotate_right` lowering for Rust's LLVM funnel-shift
   rotate forms. `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 38 unit
   tests and all three end-to-end tests with the PS3 SPU binutils on `PATH`.
   Object disassembly checked variable `rot` and constant `roti` instructions.
   The emulator script passed both directions for counts 0, 1, 31, 32, 33,
   and `0xffffffff`, plus constant five-bit rotations; each image reached
   `stop` and wrote the expected mailbox word. The emulator verifies only this
   tested subset, not hardware execution or other rotate instructions.
22. Added `u32::leading_zeros` lowering from `llvm.ctlz.i32` with its
   zero-undef flag set to false to SPU `clz`. The end-to-end object test
   assembled and disassembled the instruction. `SPU_REQUIRE_E2E=1 cargo test
   --offline` passed all 41 unit tests and all three end-to-end tests. The
   emulator returned 32 for zero, 31 for one, 0 for `0x80000000` and
   `0xffffffff`, and 11 for `0x00100000`, reaching `stop` for every image.
23. Added `u32::count_ones` lowering from `llvm.ctpop.i32` to `cntb`, `sumb`,
   and `xshw`. The SPU object integration test assembled and inspected that
   sequence; the full run passed all 43 unit tests and all three end-to-end
   tests. `spu-gcc -O1 -S` for a C `__builtin_popcount` reference emitted the
   same three instructions. The pinned `anergistic` source returns immediately
   for `sumb`, so count-ones emulator cases are opt-in in the script. For this
   run, a local, temporary emulator build implemented `sumb` according to the
   SPU ISA definition; the emulator then returned 0, 1, 1, 16, and 32 for
   `0`, `1`, `0x80000000`, `0xf0f00f0f`, and `0xffffffff` respectively, with
   each image reaching `stop`. That emulator patch is not in this repository.
24. Built GCC 9.5 `libgccjit` as a host-shared library targeting `spu` outside
   the repository and used its C API to emit a relocatable object. `spu-readelf`
   confirmed ELF32, big endian, and machine `SPU`; `spu-objdump` showed the
   native add instruction and SPU return. The current `rustc_codegen_gcc`
   plugin could not load this library because GCC 9.5 lacks
   `gcc_jit_type_get_restrict`; Rust code generation was not reached. A stock
   nightly rustc probe with `llvm-target: spu-unknown-none` independently
   failed because LLVM 23 has no SPU target.
25. Added `u32::trailing_zeros` lowering for `llvm.cttz.i32` with defined-zero
   semantics. The SPU sequence computes the low set bit, applies `clz`, and
   corrects the zero input to 32; the object test assembled and inspected every
   instruction. `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 45 unit tests
   and all three end-to-end tests. The stock emulator returned 32, 0, 3, 31,
   20, and 0 for inputs `0`, `1`, `8`, `0x80000000`, `0xf0f00000`, and
   `0xffffffff`; each image reached `stop` and wrote the expected mailbox word.
26. Added emulator-covered `u32::leading_ones` and `u32::trailing_ones` examples.
   rustc emits a bitwise complement followed by `ctlz.i32` or `cttz.i32`; the
   existing count lowering handles both without a new SPU instruction. The
   object integration test checked those instruction sequences. The full run
   passed all 45 unit tests and all three end-to-end tests, and the stock
   emulator returned 0, 1, 4, and 32 for leading-one inputs `0`,
   `0x80000000`, `0xf0f00000`, and `0xffffffff`; it returned 0, 1, 2, 0, and
   32 for trailing-one inputs `0`, `1`, `3`, `0x80000000`, and `0xffffffff`.
   Each image reached `stop` and wrote the expected mailbox word.
27. Added `i32::wrapping_abs` lowering for `llvm.abs.i32` with the poison flag
   false. The native code creates the sign mask with `rotmai`, applies XOR, and
   subtracts the mask; the object test assembled and checked this sequence.
   `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 47 unit tests and all
   three end-to-end tests. The stock emulator returned 0, 5, 5, `0x80000000`,
   and `0x7fffffff` for zero, positive five, negative five, `i32::MIN`, and
   `i32::MAX`; each image reached `stop` and wrote the expected mailbox word.
28. Added signed and unsigned scalar `min`/`max` lowering for LLVM's `smin`,
   `smax`, `umin`, and `umax` intrinsics. SPU object tests assembled each
   compare-and-`selb` sequence and checked its disassembly. `SPU_REQUIRE_E2E=1
   cargo test --offline` passed all 49 unit tests and all three end-to-end
   tests. The stock emulator script passed the existing scalar cases and new
   signed and unsigned min/max cases, including comparisons across zero and
   `0x80000000`, negative operands, and equal values. As before, the pinned
   emulator skipped `count_ones` cases because its `sumb` instruction is a stub.
29. Added unsigned `u32::saturating_add` lowering from `llvm.uadd.sat.i32`.
   Object tests assembled and inspected the native add/compare/OR sequence.
   `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 50 unit tests and all
   three end-to-end tests. The stock emulator passed cases that overflow to
   `0xffffffff`, reach `u32::MAX` without overflow, and produce an ordinary
   non-saturated sum. The count-ones emulator cases remained skipped because
   the pinned emulator's `sumb` instruction is a stub.
30. Added straight-line LLVM `select i1` lowering with i32 arms. Unit coverage
   checks compare masks, constant conditions and arms, and rejects non-i1
   conditions. Object integration tests compiled two Rust conditional examples
   and inspected `selb`; `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 53
   unit tests and all three end-to-end tests. The stock emulator passed 74
   mailbox checks across the complete script, including both selection arms
   and a conditional whose arms compute arithmetic results. General branches,
   loops, and `phi` nodes remain unsupported.
31. Added unsigned `u32::saturating_sub` lowering from `llvm.usub.sat.i32`.
   The native sequence compares before overwriting the left operand, subtracts,
   then inverts the underflow mask to clear the result to zero. It does not use
   SPU `$0` as a zero register because `$0` is the link register. Object
   integration tests verified the assembled instructions, and
   `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 54 unit tests and all
   three end-to-end tests. The stock emulator passed 78 mailbox checks across
   the suite, including underflow from zero, exact subtraction, ordinary
   subtraction, and subtraction across the sign bit. Count-ones checks were
   skipped because this emulator build leaves `sumb` unimplemented.
32. Added signed `i32::saturating_add` and `saturating_sub` lowering from
   `llvm.sadd.sat.i32` and `llvm.ssub.sat.i32`. SPU XOR/AND and `rotmai`
   instructions detect signed overflow; `selb` selects the appropriate signed
   limit. Object integration tests assembled and inspected both sequences.
   `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 55 unit tests and all
   three end-to-end tests. The stock emulator passed 86 mailbox checks across
   the suite, including positive and negative overflow, ordinary operations,
   and no-overflow cases at the signed boundaries. Count-ones execution was
   skipped because the stock emulator still leaves `sumb` unimplemented.
33. Rebuilt the pinned `rustc_codegen_gcc` checkout without its `master` feature
   against nightly rustc 1.101.0 to check compatibility with the locally built
   GCC 9.5 SPU `libgccjit`. The plugin itself built, but rustc stopped while
   loading the library at the missing `gcc_jit_function_get_return_type` API;
   no Rust code reached GCC code generation. Comparing the no-`master` binding
   API with the library's exported symbols found 44 missing symbols. The
   default plugin build additionally requires `gcc_jit_type_get_restrict`.
   The GCC 9.5 object smoke therefore remains a C API proof only, not a Rust
   codegen path.
34. Added `u32::reverse_bits` lowering from `llvm.bitreverse.i32` using four
   masked word-swap stages and a final 16-bit rotate. The object integration
   test assembled the Rust example and checked its disassembly; a unit test
   also checks that lowering preserves its input if it remains live. With the
   SPU binutils available, `SPU_REQUIRE_E2E=1 cargo test --offline` passed all
   58 unit tests and all three end-to-end tests. The pinned emulator script
   passed 91 mailbox checks overall, including reverse-bits results of zero,
   `0x80000000`, one, `0xe6a2c480`, and `0xffffffff` for zero, the low bit,
   the high bit, `0x01234567`, and all ones. Each image reached `stop`.
   Population-count execution remained skipped because this emulator leaves
   `sumb` unimplemented.
35. Added `u32::swap_bytes` lowering from `llvm.bswap.i32` using a
   `0x00ff00ff` mask, two byte shifts, and a final 16-bit rotate. The object
   integration test assembled the Rust example and checked the emitted
   instruction; unit tests check constant folding and preserve a still-live
   input. `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 62 unit tests and
   all three end-to-end tests. The pinned emulator script passed 95 mailbox
   checks overall, including byte swaps for zero, one, `0x12345678`, and all
   ones; each image reached `stop`. Count-ones execution remained skipped
   because the emulator leaves `sumb` unimplemented.
36. Separately tested a legacy direct Rust codegen path outside this
   repository. I built `rustc_codegen_gcc` at commit
   `54d2ec1a82d2a5fd0732264d5c91fc8e01f12832` with nightly rustc
   `1.59.0-nightly (78fd0f633 2021-12-29)` and GCC 9.5 `libgccjit` configured
   for `spu`. The temporary build needed GCC 9.5 API enum remapping, 33
   no-op compatibility symbols for unused newer APIs, an external-driver
   setting, and an x86-only guard around the adapter's `-masm=intel` option.
   Its custom target JSON used `arch: "powerpc"` and a PowerPC LLVM triple as
   placeholders because this rustc cannot accept SPU as a C-ABI architecture
   and has no LLVM SPU backend. With that setup, rustc compiled a one-argument
   `#![no_core]` Rust identity function to an ELF32 big-endian `EM_SPU`
   object. I linked a small startup that passed 42, called the Rust function,
   and wrote the return value to the outbound mailbox. The pinned emulator
   reached `stop` and wrote `00 00 00 2a`. A constant-return probe failed in
   the adapter with a null GCC JIT rvalue. This validates only that isolated
   identity path; the adapter patches, compatibility shim, and target JSON
   are not part of this project and do not establish a supported Rust SPU
   target or `core` support.
37. Added the first stack-passed scalar argument to the integrated prototype.
   GCC 9.5 SPU reference code for a 73-argument C function reads the 73rd
   `i32` with `lqd` from `32($sp)`; its caller reserves 48 bytes and writes
   that argument slot before the call. The Rust frontend now accepts up to 73
   parameters, loads the final one into `$75`, and rejects larger signatures.
   Scalar startup reserves the same 48-byte caller frame and stores its
   image-time 73rd word at `32($sp)`. The new Rust example returns that
   parameter. `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 64 unit tests
   and all three end-to-end tests. The pinned emulator script passed 97
   mailbox checks, including a 73rd argument of 42 and the full-width value
   `0x12345678`; count-ones remained skipped because the emulator does not
   implement `sumb`. At this validation point, the prototype covered only the
   first overflow `i32` argument; the later three-argument extension is below.

38. Extended the scalar ABI experiment to three overflow arguments. The
   installed GCC 9.5 SPU backend generates a callee load at `32($sp)` for the
   73-argument case, `48($sp)` for the 74-argument case, and `64($sp)` for the
   75-argument case. Its generated caller for 75 arguments reserves 80 bytes
   and writes the three overflow values at offsets 32, 48, and 64. The Rust
   prototype now supports up to three stack-passed `i32` arguments, loading them
   into `$75` through `$77`; startup reserves 32 bytes plus 16 bytes per stack
   argument. A Rust example sums three stack arguments, and the emulator
   returns 7 for inputs 1, 2, and 4. This differs from the 8-byte scalar slots
   recorded for the historical LLVM backend, so full ABI compatibility remains
   unclaimed. `SPU_REQUIRE_E2E=1 cargo test --offline` passed 66 unit tests and
   all three end-to-end tests. The emulator passed 98 mailbox checks; its
   count-ones cases remain skipped because this emulator build lacks `sumb`.

39. Rust unary bitwise NOT is emitted as `xor i32 value, -1`. The prototype
   now recognizes that form and lowers it to the SPU `nor` instruction with
   the input used as both sources, avoiding an all-ones materialization and a
   separate XOR. The installed GCC 9.5 SPU compiler emits the same instruction
   for C `~value`. Unit tests cover both LLVM operand orders, object tests check
   the assembled instruction, and emulator cases cover zero and a mixed bit
   pattern. `SPU_REQUIRE_E2E=1 cargo test --offline` passed 67 unit tests and
   all three end-to-end tests. The emulator passed 100 mailbox checks, with
   count-ones skipped because this emulator build lacks `sumb`.

40. Rust `u32::wrapping_neg` and `i32::wrapping_neg` emit `sub i32 0, value`.
   GCC 9.5 lowers the same expression to `sfi $3,$3,0`; the Rust backend
   now uses that instruction directly instead of materializing zero and
   subtracting. Unit and object tests cover the lowering for both Rust types,
   and emulator cases check zero, one, the high bit, a mixed full-width value,
   signed negative one, and `i32::MIN`. `SPU_REQUIRE_E2E=1 cargo test --offline`
   passed 68 unit tests and all three end-to-end tests. The emulator passed 106
   mailbox checks; count-ones remains skipped because this emulator build lacks
   `sumb`.

41. Added `--runtime-args` for ELF builds. The generated startup initializes
   the local-store stack and environment registers, then calls the Rust
   function without overwriting `$3` through `$6`. It accepts up to four
   `i32` parameters and rejects a larger signature. The object/link integration
   test checks the ELF machine and startup instruction order, including that
   the two input registers used by `add_u32` remain untouched. The optional
   emulator case seeded `$3 = 0x12345678` and `$4 = 0x5678` with the pinned
   `anergistic` build's `-r` option; the image reached `stop` and recorded
   mailbox `0x1234acf0`. `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 69
   unit tests and all four end-to-end tests. The emulator script completed with
   the runtime-argument case enabled; count-ones remained skipped because
   `sumb` is unimplemented. This checks 32-bit register forwarding only. It
   does not verify how PS3 `sysSpuThreadInitialize` maps its four 64-bit
   `sysSpuThreadArgument` values, does not test PPU loading, and does not pass
   PPU effective addresses for DMA.

42. Rechecked toolchain availability while evaluating the PPU-loader step. The
   pinned Linux toolchain archive matched SHA-256
   `66afbfc725221d3a6f02f219a6ce47ee793ff6b0890f176a9d10d2c89c91dda5` and
   contains both `ps3dev/spu` and `ps3dev/ppu`. The extracted PPU GCC is 13.2.
   The project-pinned Rust 1.99.1 target list still has neither a Sony PS3 PPU
   nor SPU target. Installed nightly 1.101 lists `powerpc64-sony-ps3`, but no
   SPU target. A separate `#![no_std]` PPU Rust crate also built as an rlib
   using `-Z build-std=core`. PSL1GHT was built locally against the extracted
   toolchain. These checks established a PPU build path, not SPU support.
43. Added `ppu-loader/`, a Rust `#![no_std]` PPU entry point with a C bridge
   using PSL1GHT's SPU image and thread APIs. Built it with
   `make -C ppu-loader PS3DEV=/tmp/ps3dev/ps3dev
   PSL1GHT=/tmp/psl1ght-install`, Rust nightly `2026-10-26`, and
   `powerpc64-ps3-elf-gcc`. `ppu-readelf -h` identified the linked output as
   big-endian ELF64 `EXEC`, machine PowerPC64, ABIv1; `ppu-nm` showed the Rust
   `main`, C `spu_loader_run`, and PSL1GHT `_start`. The launcher source opens
   an SPU ELF, creates/starts/joins a one-thread group, and reads the SPU thread
   exit status. It defaults to `/app_home/scalar.elf` and passes four zero
   thread arguments. The build does not verify execution, image loading, or
   status retrieval in RPCS3 or on PS3 hardware. The supplied `rust-ps3`
   project was inspected as a PPU reference; its README marks SPU tooling as
   future work, and none of its code is included here.
44. Reran `scripts/test-spu-emulator.sh` with the pinned `anergistic` binary and
   register presets enabled. Every enabled case passed, including the
   `--thread-exit` image, runtime `$3`/`$4` forwarding, the stack-argument
   cases, arithmetic, shifts, rotates, comparisons, saturating operations,
   selects, and bit operations. The script skipped `count_ones` because this
   emulator build has no `sumb` implementation. This does not execute the PPU
   launcher or verify PS3 thread exit-status retrieval.
45. With the SPU toolchain on `PATH`, `SPU_REQUIRE_E2E=1 cargo test --offline`
   passed all 70 unit tests and all five end-to-end tests. The end-to-end suite
   includes the runtime-register startup and `stop 0x102` thread-exit ELF
   checks. `cargo fmt --all -- --check`, `rustfmt --check --edition 2021
   ppu-loader/src/lib.rs`, and `git diff --check` also passed.
46. Added lowering for a non-volatile, at-least-4-byte-aligned `i32` load
   through a named opaque-pointer parameter, interpreting that pointer as a
   32-bit SPU local-store address. The output `ori`/`lqd`/`rotqby` sequence
   matches the sequence from `spu-gcc -O1` for a C scalar load. The native
   object integration test passed. The emulator preloaded four big-endian
   words at local-store address `0x1000`; register-preset addresses at offsets
   0, 4, 8, and 12 returned `0x12345678`, `0x89abcdef`, `0xfedcba98`, and
   `0x0badf00d` through the mailbox, with every image reaching `stop`.
   `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 73 unit tests and all
   five end-to-end tests. The full emulator script also passed; it still skips
   `count_ones` on this emulator's unimplemented `sumb`.
47. Added lowering for a non-volatile, at-least-4-byte-aligned `i32` store
   through a named local-store pointer parameter. The `lqd`/`cwd`/`shufb`/`stqd`
   sequence matches `spu-gcc -O1` for a C reference store, and the integration
   test assembles and checks its instructions. `SPU_REQUIRE_E2E=1 cargo test
   --offline` passed all 75 unit tests and all five end-to-end tests. The
   emulator returned the stored value and wrote `0xdeadbeef` at local-store
   offsets 0, 4, 8, and 12 while preserving the other three preloaded words
   each time. The full script passed; `count_ones` remains skipped because
   this emulator does not implement `sumb`.
48. Revisited the legacy Rust codegen experiment with nightly rustc
   `1.59.0-nightly (78fd0f633 2021-12-29)`, the 2021 `rustc_codegen_gcc`
   adapter, and the host-shared GCC 9.5 SPU `libgccjit` build. A custom target
   JSON with `arch: "spu"` reports `target_arch="spu"` and the expected
   32-bit, big-endian cfg; its `llvm-target` remains the PowerPC placeholder
   `powerpc-unknown-none` because stock LLVM has no CellSPU backend. A Rust-ABI
   `#![no_core]` identity function compiled to ELF32 big-endian `EM_SPU`, linked
   with a small SPU assembly entry point, and ran in `anergistic`; it returned
   42 through mailbox channel 28. This experiment uses an adapter patched for
   GCC 9.5 plus a temporary shim providing 33 unused newer API symbols. It is
   not wired into this repository and does not establish a supported Rust
   target. The same old compiler rejects `extern "C"` for `arch: "spu"`. A
   direct path-dependency probe using `core` and `u32::wrapping_add` reached
   code generation but the adapter panicked on `unsigned char` vector size 2.
   A separate temporary shim implemented vector introspection against GCC
   9.5's internal JIT type objects and got past that panic; the next run failed
   while lowering a core aggregate constant, with null GCC JIT values and field
   types. Follow-up instrumentation traced the first null value to
   `gcc_jit_context_new_array_constructor`: GCC 9.5 does not export this newer
   API, and the temporary compatibility library supplied a no-op null-returning
   stub for it. Consequently, byte-array constants reach the backend as null
   before the containing aggregate is built. Cargo also reported that it could
   not find `compiler_builtins` for the target. No `core`-using function was
   produced or run. These checks show
   progress on a narrow codegen route while leaving the target backend, C ABI,
   and `core` support unresolved.
49. Added `experiments/legacy-rustc/` with the custom target JSON, `#![no_core]`
   Rust-ABI identity and `u32` addition examples, SPU startup assembly, and a
   repeatable test script. The addition example calls the compiler's
   `wrapping_add` intrinsic without linking `core`. The target cfg reports
   `target_arch="spu"`, big endian, and 32-bit pointers; its data layout matches
   the one recorded for historical LLVM CellSPU. Ran
   `scripts/test-legacy-rustc-backend.sh` with the external patched 2021
   `rustc_codegen_gcc`, GCC 9.5 SPU `libgccjit`, compatibility shim, SPU
   binutils, and `anergistic`. The script verified ELF32 big-endian `EM_SPU`
   objects, checked that the addition object contains native `a $3,$3,$4`,
   linked both into SPU executables, reached `stop`, and received `42` and
   `0x1234acf0` in mailbox channel 28. The backend/shim are external; this is
   not a rustc built-in target or a `core` build.
50. Re-ran `SPU_REQUIRE_E2E=1 cargo test --offline` with the PS3 SPU binutils
   on `PATH`: all 75 unit tests and all 5 assembler/linker end-to-end tests
   passed. Ran `scripts/test-spu-emulator.sh` with the pinned `anergistic`
   emulator and register presets enabled; all enabled scalar, local-store,
   stack-argument, and runtime-register cases reached `stop` and returned the
   expected mailbox words. The script skipped population-count cases because
   this emulator build leaves `sumb` unimplemented. No hardware or PS3 PPU
   launcher execution was tested.
51. Extended the Rust PPU loader to parse up to four decimal or `0x`-prefixed
   `u64` arguments after an optional image path and pass them through the C
   bridge into PSL1GHT's `sysSpuThreadArgument` fields. Its four parser and
   argument-count tests
   passed. `make -C ppu-loader PS3DEV=/tmp/ps3dev/ps3dev
   PSL1GHT=/tmp/psl1ght-install` cross-built and linked the loader; `ppu-readelf`
   confirmed a big-endian ELF64 PowerPC64 executable with ABI v1, and `ppu-nm`
   found the Rust `main`, C bridge, and PSL1GHT `_start`. This verifies argument
   parsing and field passing at build time only. The mapping from those 64-bit
   syscall fields to the SPU entry registers, PPU loading, and runtime behavior
   remain unverified.
52. Added an experimental `--ppu-thread-args` startup adapter. It converts up
   to four incoming 64-bit argument registers to the low 32-bit words expected
   by scalar Rust parameters, using `shlqbyi ...,4` as observed in the
   installed SPU GCC ABI. The E2E test confirmed the emitted conversion and
   call sequence. The emulator passed two-argument and four-argument cases
   with distinct high and low words (`0x11111100` and `0x0000000f`), alongside
   the existing enabled cases. These register presets validate the SPU
   adapter, not the PPU syscall path: the loader has not run in RPCS3 or on
   hardware, and the runtime mapping from `sysSpuThreadArgument` to entry
   registers remains unverified.
53. Compared the relevant GCC versions for the legacy `core` route. GCC 10.1's
   `config.gcc` rejects `spu*-*-*`; the installed GCC 9.5 build has the SPU
   backend but its `libgccjit` lacks aggregate constructor APIs. GCC 12 release
   notes add those constructor and rvalue-global-initializer APIs, while its
   config also rejects SPU. There is no tested stock version pairing; the
   likely compatibility experiment is to backport the required JIT APIs to the
   SPU-capable GCC 9.5 build. This route has not yet been implemented.
54. Ported the historical CellSPU selector, lowering, and assembly-printer
   sources far enough to build the full `LLVMCellSPUCodeGen` library and
   `llc` against LLVM 23.1.1 commit
   `6dfe1677ab8dffbc6ec13d53a1e0215d75147689`. A runtime crash on the first
   function traced to LLVM 23 querying `SelectionDAGTargetInfo` for a target
   return node when the historical subtarget supplied none; adding the default
   target DAG-info object fixed the failure.
55. Added `scripts/test-llvm-cellspu-backend.sh`. Pinned host rustc compiled a
   `#![no_std]` scalar fixture to host-target LLVM IR; the custom `llc` was
   explicitly retargeted to CellSPU and compiled add, subtract, AND, OR, XOR,
   increment, constant return, and equality with `-verify-machineinstrs`. GNU
   SPU binutils assembled the output, verified its ELF32 big-endian relocatable
   object with machine `SPU`, and linked an entry wrapper to `ET_EXEC`. The
   emulator program reached `stop` and wrote nine expected words to outbound
   mailbox channel 28, including `0x000068ac` for addition and normalized
   `1`/`0` for equality. This is not `rustc --target=spu`; the smoke fixture
   contains no pointers. The emulator ran in the test's temporary directory so
   its default local-store dump did not affect repository files.
56. Tried LLVM's direct `llc -filetype=obj` path; it reports
   `createMCCodeEmitter failed`. LLVM object emission remains unsupported and
   the working path uses the GNU SPU assembler and linker. The smoke path starts
   with Rust source compiled by host rustc, then retargets that IR with custom
   `llc`; it does not demonstrate a maintained `rustc --target=spu`, SPU
   `core`, or PPU loading.
57. Extended `scripts/test-llvm-cellspu-backend.sh` with unoptimized Rust
   `max_u32` and `max_i32` conditionals. LLVM's `BR_CC` legalization was keyed to the compared
   type, so correcting the backend action from `MVT::Other` to `MVT::i32` let
   the existing compare-and-branch patterns select `clgt` and `brnz`. The new
   path exposed invalid memory-effect flags on the generated stack-slot
   read/modify/write, malformed frame-save store operands, and branch-analysis
   hooks whose historical names did not override LLVM 23's lowercase APIs;
   these were corrected. `llc -verify-machineinstrs` now passes, GNU SPU
   binutils assemble and link the object, and the emulator returns `0x5678`
   and `0x9876` for the unsigned false and true paths, plus `5` and `7` for
   signed paths across zero. The wrapper initializes `$sp` to `0x3f000`, inside
   the 256 KiB local store. The repeatable script passed with all thirteen
   mailbox results. A separate Rust `max_u16` probe still fails selection at
   `i16 BR_CC`; that type needs branch-compare lowering. The tested paths cover
   signed and unsigned i32 greater-than branches and their generated stack
   frames, not loops, general `phi`, pointer-memory, or complete ABI support.
58. The first Rust pointer load/store probe exposed a post-register-allocation
   crash: the historical `copyPhysReg` declaration did not override LLVM 23's
   current hook, so copy expansion reached LLVM's unreachable default. Updated
   the backend method signature and renamable-register handling. The smoke
   fixture now includes unsafe `*const u32` and `*mut u32` functions. Since
   host rustc emits the host data layout, the script explicitly rewrites the
   module triple and data layout to CellSPU's big-endian, 32-bit-pointer
   layout before `llc`; this remains a bootstrap test, not a rustc target.
   The wrapper loads the first and fourth words of a 16-byte local-store block,
   stores `0xaabbccdd` into the second word, then reloads all four. The three
   neighboring values remain unchanged. Machine verification, assembly, link,
   and emulator execution pass; the full mailbox now contains nineteen
   expected words. This covers aligned word accesses within one quadword only.
59. Added direct LLVM `BR_CC` TableGen patterns for signed and unsigned i16
   greater-than conditions. Expanding or promoting `BR_CC i16` through LLVM's
   generic legalization left an unselectable `i32 SETCC` over i16 operands;
   the direct patterns select native `cgth`/`clgth` followed by `brhnz`.
   Rust `max_i16` and `max_u16` functions now exercise both branch outcomes.
   A test-only C caller compiled with SPU GCC consumes and widens their narrow
   return values, validating that ABI boundary against the GNU toolchain. The
   repeatable smoke script checks the instructions and emulator results `5`,
   `7`, `0x5678`, and `0x9876`; all twenty-three mailbox results pass. This
   covers only signed and unsigned greater-than branch predicates, not other
   i16 comparisons or the full narrow-integer ABI.
60. Added an unoptimized Rust `sum_to_n` function with a `while i < n` loop to
   the backend smoke fixture. The generated IR uses stack-backed loop values;
   the backend selects the unsigned comparison, loop backedge, and branch
   layout. `llc -verify-machineinstrs`, GNU assembly/link, and emulator
   execution pass. Inputs `0`, `1`, `5`, and `10` return `0`, `0`, `10`, and
   `45`, respectively. The repeatable smoke test now checks twenty-seven
   mailbox results. This exercises one stack-backed loop shape; it does not
   validate optimized loops or general LLVM `phi` lowering.
61. Added an optimized Rust loop with two loop-carried `phi` values and a
   no-inline helper call. LLVM 23's call-frame pseudos needed both frame-size
   operands, and the historical SPU frame-pseudo removal hook had moved from
   register info to frame lowering. Ported those pieces and included the return
   registers as operands of the SPU return node so post-register-allocation
   cleanup keeps a helper's result live. The function now passes
   `-verify-machineinstrs`, assembles and links, and returns `0`, `3`, `7`, `25`,
   and `75` for inputs `0`, `1`, `2`, `5`, and `10` in the emulator. The repeatable
   smoke test now checks thirty-two mailbox results. This exercises one
   optimized loop shape and ordinary helper call; it does not establish general
   loop, call, or `phi` support.
62. Added branch fixtures for the remaining `i32` comparison predicates. Both
   true and false cases now pass for equality, inequality, signed less-than,
   less-or-equal, greater-or-equal, and unsigned less-than, less-or-equal, and
   greater-or-equal; existing signed and unsigned greater-than cases complete
   all ten predicates. The expanded fixture exposed a mailbox checker issue:
   `od` compressed repeated rows, so the checker now requests uncompressed
   output before comparing bytes. Machine verification, SPU assembly and link,
   and emulator execution pass for all forty-eight expected results. Other
   `i16` branch predicates remain untested.
63. Added direct `BR_CC i16` TableGen patterns for equality, inequality, signed
   less-than/less-or-equal/greater-or-equal, and unsigned
   less-than/less-or-equal/greater-or-equal. They use native halfword equality
   or reversed compare operands with the appropriate zero/nonzero halfword
   branch. The emulator now checks both outcomes of all ten signed and
   unsigned `i16` comparison predicates as well as all ten `i32` predicates,
   returning sixty-four expected mailbox words across the complete smoke run.
64. Reconciled scalar overflow-argument lowering with the installed GCC 9.5
   SPU ABI. Overflow scalar slots now use 16-byte spacing; outgoing stack stores
   are chained after `CALLSEQ_START`; and incoming stack arguments receive the
   caller-linkage-area adjustment when the Rust callee allocates a frame. The
   target now constructs its per-function `SPUFunctionInfo` through LLVM's
   `createMachineFunctionInfo` hook. The smoke fixture checks the 73rd `u32`
   argument in three ways: a GCC call to a Rust leaf, a GCC call to Rust code
   that forwards all 73 dynamic values to another Rust function, and a
   Rust-generated call with 72 zero constants plus `0x12345678`. Each path
   returns `0x12345678` in the emulator. Constant vectors created by call
   lowering use the existing SPU constant-pool load path. The full smoke run
   now checks sixty-seven mailbox words. Other overflow scalar widths, vectors,
   varargs, and the rest of the ABI remain unverified.
65. Expanded the direct-rustc experiment from `u32` addition to `u64`
   addition/subtraction and bitwise AND. This exposed missing MC encodings for
   `cg`/`addx`, `bg`/`sfx`, and `iohl`; the bitwise/truncation path was not
   runnable until the latter was added. The subtraction regression also
   exposed that the historical pattern passed operands in the wrong order for
   SPU's subtract-extended operation. The maintained emitter now supports these
   forms and TableGen reverses the subtraction operands. The test compares
   `cg`, `addx`, `bg`, `sfx`, `and`, and `iohl` words byte for byte with GNU SPU
   binutils. The emulator checks eight results covering carry, no carry,
   constant high-word addition, borrow, no borrow, constant high-word
   subtraction, and both halves of 64-bit AND; all pass and reach `stop`.
   This remains a minimal `#![no_core]` Rust-ABI experiment and does not build
   `core` or provide an in-tree rustc target.
66. Attempted a real `cargo -Z build-std=core` build for the experimental target,
   routing host build scripts through the installed host rustc and target
   objects through the custom CellSPU rustc. After adding the pinned `rust-src`
   component, Cargo built the host setup and invoked rustc on the actual `core`
   crate. Rustc then panicked while computing the C ABI of
   `core::ffi::VaList` with `no lowering implemented for spu`. No SPU `core`
   artifact was produced. This confirms that foreign-ABI support in rustc's
   target call-convention layer, which runs before LLVM, is a required next
   integration step; choosing a different ABI or skipping the type would not
   establish a correct target.
67. Extended the direct-rustc `#![no_core]` fixture to compile constant and
   variable `u64` left shifts through the maintained CellSPU LLVM
   backend. The LLVM selector already formed the sequences, but the MC encoder
   lacked `fsmbi`, `selb`, `shlqby`, `shlqbi`, `shlqbyi`, and `shlqbii` encodings.
   Added those plus encoding comparisons for `andi` and `rotmi`.
   `scripts/test-rustc-cellspu.sh`
   compares these instruction words with GNU SPU binutils, links the ELF, and
   checks 38 mailbox values in the emulator. Variable counts 0, 1, 7, 8, 31,
   32, 40, 63, 64, and 65 all produced the expected high and low words; counts
   64 and 65 verify count masking. A constant shift by 13 also passes. The
   wrapper passes three distinct `u64` values in registers at runtime; only
   those input patterns are covered. This still uses Rust ABI and an
   experimental target JSON and does not build `core` or ordinary `#![no_std]`
   crates.
68. Extended the same direct-rustc fixture with unsigned `u64` logical-right
   shifts and signed `i64` arithmetic-right shifts, both with variable counts
   and with a constant shift by 13. The maintained MC encoder gained the
   `rotqmby`, `rotqmbi`, `rotqmbyi`, `rotqmbii`, `fsm`, `rotqbybi`, `rotqbi`,
   `rotqbyi`, and `rotqbii` encodings needed by the selector. The script
   reassembles each selected instruction form with GNU SPU binutils and checks
   all emitted encodings byte for byte. The emulator now checks 88 total
   mailbox results: 50 more than the left-shift milestone, including negative
   signed inputs, positive signed values, counts 0, 1, 7, 8, 31, 32, 40, 63,
   64, and 65, and masked counts 64 and 65. The experiment remains `#![no_core]`, uses Rust
   ABI and an experimental target JSON, and does not build `core`.
69. Added direct-rustc coverage for `u64` wrapping multiplication after object
   emission failed on the vector forms of `mpyu` and `mpyh` selected by LLVM's
   64-bit lowering. The maintained MC encoder now handles scalar and vector
   `mpyu`/`mpyh` plus scalar and vector `mpyhhu`. The script reassembles all
   three instruction forms with GNU SPU binutils and compares their encodings
   byte for byte. A separate linked image checks both words of four products
   in the emulator: `0x0000000100000002 * 0x0000000300000004`,
   `u64::MAX * 2`, `0x0123456789abcdef * 0xfedcba9876543210`, and
   `0x8000000080000000 * 0x0000000200000003`. The observed results match
   wrapping modulo-2^64 arithmetic with overflow checks disabled. The test
   covers four operand pairs and is not exhaustive; it remains a `#![no_core]`
   Rust-ABI experiment.

The emulator check covers only the exercised SPU instructions and this simple
local-store ELF layout. It does not validate the complete ISA, DMA, concurrent
SPU behavior, runtime execution of the PPU loader, PS3 firmware integration, or
physical hardware.

## Latest verification (2026-10-30)

- Installed the pinned `ps3dev/ps3toolchain` `nightly-2026-10-11` under
  `/home/longlive/opt/ps3dev/spu` using `scripts/install-spu-toolchain.sh`.
  This install is outside the repository and is not vendored.
- With the SPU bin directory on `PATH`,
  `SPU_REQUIRE_E2E=1 cargo test --offline`: all 76 unit tests and six
  end-to-end cases passed. The end-to-end suite assembled and linked native
  SPU objects and ELF images, then checked disassembly and ELF metadata.
- `scripts/test-llvm-cellspu-tablegen.sh` passed against LLVM 23.1.1 commit
  `6dfe1677ab8dffbc6ec13d53a1e0215d75147689`, generating the CellSPU target
  descriptions and applying the pinned big-endian 32-bit CellSPU triple patch.
- The LLVM 23.1.1 CellSPU code-generation library and `llc` build successfully;
  `llc --version` lists `cellspu - STI CBEA Cell SPU [experimental]`.
- `scripts/test-llvm-cellspu-backend.sh` passed with LLVM 23.1.1 `llc`, GNU SPU
  binutils 2.22, SPU GCC 9.5.0, and the pinned `anergistic` executable. It
  compiles `#![no_std]` Rust scalar fixtures, including signed and unsigned
  32-bit and 16-bit conditionals, generated stack frames, unsafe local-store
  pointer loads/stores, an unoptimized loop, and an optimized loop with
  loop-carried values and an in-loop call, to SPU object files directly from
  LLVM. The harness supplies the CellSPU
  32-bit-pointer data layout to the host-rustc IR and uses a GCC-compiled C
  caller to check the narrow return ABI. LLVM emits the objects, which GNU
  SPU binutils link before emulator execution. Machine verification passed, and
  the emulator returned ninety-one expected results, including wrapping
  `u32` multiplication results `0x369d0368` and `0xfffffffc`,
  `swap_bytes(0x12345678)` returning `0x78563412`,
  `leading_zeros` results 17 and 32, `trailing_zeros` results 31, 8, and 32,
  `count_ones` results 13, 32, and 0,
  `leading_ones` results 8 and 32, and `trailing_ones` results 4 and 32,
  both rotate directions at count 40,
  returning `0x34567812` and `0x78123456`, all ten signed and
  unsigned `i32` and `i16`
  branch predicates, immediate and explicitly masked variable left,
  logical-right, and arithmetic-right `i32` shifts, both loop cases, the
  optimized loop's helper call and return value, narrow C ABI return values,
  preserved neighboring words after a pointer store, and the 73rd `u32`
  argument through GCC-to-Rust, Rust forwarding, and Rust constant-argument
  calls. The script now exercises LLVM's experimental MC code emitter,
  big-endian assembler backend, and ELF writer. The tested path includes
  `R_SPU_REL16` helper-call relocations and `R_SPU_ADDR16` constant-pool
  references. `HBRA` branch hints are emitted as no-ops; other instruction and
  relocation forms remain unverified. Variable-shift cases explicitly mask
  counts in Rust and check counts 32, 33, and 36. The smoke check also assembles LLVM's
  textual output with GNU `spu-as` and confirms the disassembly matches the
  direct object output after excluding those dropped branch hints. This still
  does not use a maintained
  rustc SPU target or build SPU `core`. No PPU loading or hardware execution
  was tested.

- Rebuilt the maintained LLVM 23.1.1 CellSPU backend and custom rustc 1.99.1
  stage1 compiler after adding MC encodings for `cg`, `addx`, `bg`, `sfx`,
  `iohl`, and the 64-bit left and right shift sequences, plus direct 64-bit AND
  support and corrected subtraction operand order. Rustc's build glue expects PowerPC
  LLVM initializer names and a `powerpc` component, so this build uses opt-in
  CellSPU initializer aliases
  and `scripts/llvm-config-cellspu-rustc.sh`; the aliases initialize CellSPU
  only. The Rust source checkout was left unchanged.
- Ran `scripts/test-rustc-cellspu.sh` with that custom rustc, GNU SPU binutils,
  and the pinned `anergistic` emulator. Rustc directly emitted ELF32
  big-endian `EM_SPU` objects from a minimal `#![no_core]` fixture for `u32`
  addition, `u64` addition/subtraction, 64-bit bitwise AND, and constant and
  variable `u64` left and logical-right shifts, plus signed `i64`
  arithmetic-right shifts.
  Tested carry, borrow, logic, immediate, mask, rotate, and shift encodings
  match GNU SPU assembler output byte for byte. The linked emulator wrapper
  checked 88 results, including variable counts 0, 1, 7, 8, 31, 32, 40, 63, 64,
  and 65, constant shifts by 13, and signed and unsigned values; it reached
  `stop`. The fixture uses Rust ABI; rustc still panics on `extern "C"` for this
  experimental `arch = "spu"` target.
- The same direct-rustc script compiled a separate `u64` wrapping-multiply
  fixture. `mpyu`, `mpyh`, and `mpyhhu` encodings matched GNU SPU binutils;
  four product results were checked as eight mailbox words in the emulator.
  The LLVM backend suite also passed its 91 emulator results, and
  `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 76 unit and six end-to-end
  tests.
- Attempted Cargo's `-Z build-std=core` path with the custom target and a router
  that uses the host rustc for build scripts. Cargo reached the real `core`
  crate, but rustc panicked on the C ABI for `core::ffi::VaList` with `no
  lowering implemented for spu`. No `core` artifact was produced; this target
  still needs foreign-ABI lowering in rustc before ordinary `#![no_std]` support
  can be claimed.
- Reran `scripts/test-llvm-cellspu-backend.sh` against the rebuilt LLVM target.
  The separate host-rustc-to-`llc` smoke suite still passed all ninety-one
  expected emulator results and reached `stop`.
- Extended the maintained LLVM backend smoke test with twenty `i64`
  comparisons covering equality, inequality, signed and unsigned less-than,
  less-or-equal, greater-than, and greater-or-equal, including values whose
  high and low words compare in opposite directions. The emulator test exposed
  a signed `i64` greater-than pattern that used the unsigned instruction and an
  unsigned greater-or-equal pattern that did not compare the full 64-bit value.
  Both patterns were corrected; the full-width unsigned greater-or-equal path
  now compares in reverse and normalizes its mask. The MC emitter gained the
  tested `gb`, `cgti`, `xswd`, and vector `sfi` encodings; generated object bytes
  match GNU SPU binutils. `scripts/test-llvm-cellspu-backend.sh` passed all
  checks, and the emulator returned the packed comparison result
  `0x00055555` among ninety-two expected mailbox words before reaching `stop`.
- Re-ran `scripts/test-rustc-cellspu.sh` with the custom stage1 rustc, GNU SPU
  binutils, and pinned emulator. The no-core addition fixture returned 42; the
  arithmetic and shift fixture passed 88 emulator results; and the separate
  `u64` multiplication fixture passed all four products. Then
  `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 76 unit tests and six
  end-to-end tests. This still does not build SPU `core` or provide a supported
  `rustc --target=spu` target.
- Extended the maintained LLVM backend emulator fixture with signed and
  unsigned `i8` and `i16` loads, `u8` and `u16` loads at block edges, a `u8`
  store, and a packed `u16` load/store crossing a 16-byte boundary. Added the
  missing `CBD` machine encoding. The caller verifies changed bytes and
  preserved neighbors. This exposed a frame-lowering bug: a function spill
  could use the reserved slot without allocating a frame and overwrite the
  caller's saved pointer. The CellSPU frame lowering now allocates a frame
  when local frame indices are used, while leaving the unused reserved slot
  alone.
- Rebuilt LLVM 23.1.1 `llc`. `scripts/test-llvm-cellspu-backend.sh` passed all
  103 emulator mailbox words, including the narrow and cross-boundary memory
  cases, and reached `stop`. `scripts/test-rustc-cellspu.sh` again passed its
  `#![no_core]` addition, 88 arithmetic and shift results, and four 64-bit
  products. `SPU_REQUIRE_E2E=1 cargo test --offline` passed all 76 unit and six
  end-to-end tests. Ordinary `#![no_std]` support, SPU `core`, and PPU loading
  remain unimplemented.
- Extended the CellSPU smoke fixture to read and write aligned `u64` values and
  packed `u64` values at byte offset 13, crossing a 16-byte boundary. It checks
  both halves and surrounding bytes. A GCC caller also passes two `u64`
  arguments to a Rust addition function and checks the 64-bit result. The direct
  MC object and GNU assembler disassemblies match for these instructions,
  including the `CDD` channel mask. The emulator passed all 115 mailbox words
  and reached `stop`. This covers selected 64-bit memory cases and one C ABI
  signature; it does not establish general memory or ABI support.
- Added CellSPU `R_SPU_ADDR18` support to LLVM's MC emitter and object writer for
  relocatable `ila symbol` instructions. A Rust static-pointer fixture also
  exercises the existing `R_SPU_ADDR32` data relocation. The smoke test checks
  both relocation types, links with GNU `spu-ld`, follows the pointer with
  volatile byte reads, and verifies `0x5a17c0de` in the emulator. The direct
  object and GNU-assembled disassemblies match; the complete LLVM backend smoke
  suite passed all 116 mailbox words. This does not implement the high/low
  symbol relocations needed by the large-memory address sequence, nor does it
  validate the complete SPU relocation set.
- Added `R_SPU_ADDR16_HI` and `R_SPU_ADDR16_LO` fixups for the `ILHU`/`IOHL`
  address sequence chosen by CellSPU's `+large_mem` feature. A second native
  object links its Rust static pointer at `0x10010`, forcing nonzero high and
  low relocation halves; GNU `spu-as` disassembly matched the direct LLVM object, and
  the emulator read `0x5a17c0de` through the relocated pointer. The regular
  backend image still passes all 116 results. This exercises one large-memory
  static-pointer path; it does not validate every large-memory access or the
  full relocation set.
- Replaced the CellSPU MC emitter's `HBRA` no-op with a native branch-hint
  encoding. Its local branch-instruction field uses a PC-relative word offset,
  while the hinted target uses `R_SPU_ADDR16`. The direct LLVM object now
  matches GNU `spu-as` for the optimized-loop branch hint, and the emulator
  still passes all 116 main results. This validates encoding and execution,
  not a performance benefit from the hint.
