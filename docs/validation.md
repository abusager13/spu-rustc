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

The emulator check covers only the exercised SPU instructions and this simple
local-store ELF layout. It does not validate the complete ISA, DMA, concurrent
SPU behavior, a PPU loader, PS3 firmware integration, or physical hardware.
