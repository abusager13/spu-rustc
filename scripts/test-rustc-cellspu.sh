#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
rustc=${RUSTC:-rustc}
llvm_libdir=${CELLSPU_LLVM_LIBDIR:-}
spu_as=${SPU_AS:-spu-as}
spu_ld=${SPU_LD:-spu-ld}
spu_readelf=${SPU_READELF:-spu-readelf}
spu_objdump=${SPU_OBJDUMP:-spu-objdump}
emulator=${SPU_EMULATOR:-anergistic}

if [[ -n "$llvm_libdir" ]]; then
    export LD_LIBRARY_PATH="$llvm_libdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

for tool in "$rustc" "$spu_as" "$spu_ld" "$spu_readelf" "$spu_objdump" "$emulator" timeout; do
    if [[ "$tool" == */* ]]; then
        [[ -x "$tool" ]] || {
            echo "Required executable not found: $tool" >&2
            exit 127
        }
    else
        command -v -- "$tool" >/dev/null || {
            echo "Required tool not found: $tool" >&2
            exit 127
        }
    fi
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/rustc-cellspu.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT

cfg=$("$rustc" -Z unstable-options --print cfg \
    --target="$root/experiments/rustc-cellspu/target.json") || {
    echo "RUSTC must be a custom build with this repository's CellSPU LLVM target; see experiments/rustc-cellspu/README.md" >&2
    exit 2
}
for expected in 'target_arch="spu"' 'target_endian="big"' 'target_pointer_width="32"'; do
    grep -Fxq "$expected" <<<"$cfg" || {
        echo "Unexpected custom target cfg; expected $expected" >&2
        exit 1
    }
done

# The emulator does not implement absolute BRASL. Make a temporary target
# variant for this suite so it uses range-limited relative calls without
# changing the repository's default target configuration.
target_short_calls="$tmp/target-short-calls.json"
python3 - "$root/experiments/rustc-cellspu/target.json" \
    "$target_short_calls" <<'PY'
import json
import pathlib
import sys

target = json.loads(pathlib.Path(sys.argv[1]).read_text())
target["features"] = "+short-calls"
pathlib.Path(sys.argv[2]).write_text(json.dumps(target))
PY

"$rustc" -Z unstable-options \
    --target="$target_short_calls" \
    --crate-type=lib --emit=obj -Cpanic=abort -Copt-level=1 \
    -Cllvm-args=-verify-machineinstrs \
    -o "$tmp/add_u32.o" "$root/experiments/rustc-cellspu/add_u32.rs"

header=$("$spu_readelf" -h "$tmp/add_u32.o")
for expected in "Class:                             ELF32" \
    "Data:                              2's complement, big endian" \
    "Machine:                           SPU"; do
    grep -Fq "$expected" <<<"$header" || {
        echo "Unexpected Rust object header; expected $expected" >&2
        exit 1
    }
done

disassembly=$("$spu_objdump" -dr "$tmp/add_u32.o")
grep -Eq 'a[[:space:]]+\$3,\$4,\$3' <<<"$disassembly" || {
    echo "Rust addition object did not contain native SPU a $3,$4,$3" >&2
    exit 1
}

"$spu_as" -o "$tmp/start.o" "$root/experiments/rustc-cellspu/start.s"
"$spu_ld" -Ttext=0 -e _start -o "$tmp/add_u32.elf" \
    "$tmp/start.o" "$tmp/add_u32.o"

header=$("$spu_readelf" -h "$tmp/add_u32.elf")
for expected in "Class:                             ELF32" \
    "Data:                              2's complement, big endian" \
    "Type:                              EXEC (Executable file)" \
    "Machine:                           SPU"; do
    grep -Fq "$expected" <<<"$header" || {
        echo "Unexpected Rust executable header; expected $expected" >&2
        exit 1
    }
done

if ! (cd "$tmp" && ANERG_MBOX="$tmp/mailbox" \
    timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" "$tmp/add_u32.elf") \
    >"$tmp/emulator.log" 2>&1; then
    cat "$tmp/emulator.log" >&2
    echo "Rust CellSPU emulator run failed or timed out" >&2
    exit 1
fi
grep -Fq '####### stop instruction reached:' "$tmp/emulator.log" || {
    cat "$tmp/emulator.log" >&2
    echo "Rust CellSPU image did not reach stop" >&2
    exit 1
}

actual=$(od -An -N4 -tx1 "$tmp/mailbox" | tr -d '[:space:]')
[[ "$actual" == 0000002a ]] || {
    echo "Expected Rust addition result 0000002a, got ${actual:-<empty>}" >&2
    exit 1
}

echo "rustc 1.99 CellSPU no_core u32 addition: ELF32 big-endian EM_SPU; native a instruction; emulator returned 42 and reached stop"

"$rustc" -Z unstable-options \
    --target="$target_short_calls" \
    --crate-type=lib --emit=obj -Cpanic=abort -Copt-level=1 \
    -o "$tmp/u64_arithmetic.o" "$root/experiments/rustc-cellspu/u64_arithmetic.rs"

disassembly=$("$spu_objdump" -dr "$tmp/u64_arithmetic.o")
grep -Eq 'cg[[:space:]]+\$' <<<"$disassembly" || {
    echo "Rust u64 arithmetic object did not contain native SPU cg" >&2
    exit 1
}
grep -Eq 'addx[[:space:]]+\$' <<<"$disassembly" || {
    echo "Rust u64 arithmetic object did not contain native SPU addx" >&2
    exit 1
}
header=$("$spu_readelf" -h "$tmp/u64_arithmetic.o")
for expected in "Class:                             ELF32" \
    "Data:                              2's complement, big endian" \
    "Machine:                           SPU"; do
    grep -Fq "$expected" <<<"$header" || {
        echo "Unexpected Rust u64 object header; expected $expected" >&2
        exit 1
    }
done

instructions='^(cg|addx|and|bg|sfx|iohl|fsm|fsmbi|selb|andi|sfi|rotmi|shlqby|shlqbi|shlqbyi|shlqbii|rotqmby|rotqmbi|rotqmbyi|rotqmbii|rotqbybi|rotqbi|rotqbyi|rotqbii)$'
"$spu_objdump" -d "$tmp/u64_arithmetic.o" | awk -v instructions="$instructions" '
    BEGIN { print ".text" }
    $6 ~ instructions {
        printf "%s", $6
        for (i = 7; i <= NF && $i !~ /^#/; i++)
            printf " %s", $i
        print ""
    }
' >"$tmp/emitted-encoding.s"
"$spu_as" -o "$tmp/emitted-encoding.o" "$tmp/emitted-encoding.s"
reference=$("$spu_objdump" -d "$tmp/emitted-encoding.o" | \
    awk '$6 ~ /^(cg|addx|and|bg|sfx|iohl|fsm|fsmbi|selb|andi|sfi|rotmi|shlqby|shlqbi|shlqbyi|shlqbii|rotqmby|rotqmbi|rotqmbyi|rotqmbii|rotqbybi|rotqbi|rotqbyi|rotqbii)$/ { print $2 $3 $4 $5 }')
actual_encoding=$("$spu_objdump" -d "$tmp/u64_arithmetic.o" | \
    awk '$6 ~ /^(cg|addx|and|bg|sfx|iohl|fsm|fsmbi|selb|andi|sfi|rotmi|shlqby|shlqbi|shlqbyi|shlqbii|rotqmby|rotqmbi|rotqmbyi|rotqmbii|rotqbybi|rotqbi|rotqbyi|rotqbii)$/ { print $2 $3 $4 $5 }')
if [[ "$reference" != "$actual_encoding" ]]; then
    echo "LLVM SPU instruction encodings differ from GNU SPU binutils" >&2
    echo "SPU assembler: ${reference//$'\n'/ }" >&2
    echo "LLVM object:   ${actual_encoding//$'\n'/ }" >&2
    exit 1
fi

grep -Eq 'bg[[:space:]]+\$' <<<"$disassembly" || {
    echo "Rust u64 subtraction object did not contain native SPU bg" >&2
    exit 1
}
grep -Eq 'sfx[[:space:]]+\$' <<<"$disassembly" || {
    echo "Rust u64 subtraction object did not contain native SPU sfx" >&2
    exit 1
}
grep -Eq 'and[[:space:]]+\$' <<<"$disassembly" || {
    echo "Rust u64 bitwise object did not contain native SPU and" >&2
    exit 1
}
for instruction in fsmbi selb andi rotmi shlqby shlqbi shlqbyi shlqbii \
    sfi rotqmby rotqmbi rotqmbyi rotqmbii fsm rotqbybi rotqbi rotqbyi rotqbii; do
    grep -Eq "${instruction}[[:space:]]+\\$" <<<"$disassembly" || {
        echo "Rust 64-bit shift object did not contain native SPU $instruction" >&2
        exit 1
    }
done

"$spu_as" -o "$tmp/u64_start.o" \
    "$root/experiments/rustc-cellspu/u64_start.s"
"$spu_ld" -Ttext=0 -e _start -o "$tmp/u64_arithmetic.elf" \
    "$tmp/u64_start.o" "$tmp/u64_arithmetic.o"

if ! (cd "$tmp" && ANERG_MBOX="$tmp/u64_mailbox" \
    timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" "$tmp/u64_arithmetic.elf") \
    >"$tmp/u64_emulator.log" 2>&1; then
    cat "$tmp/u64_emulator.log" >&2
    echo "Rust CellSPU u64 arithmetic emulator run failed or timed out" >&2
    exit 1
fi
grep -Fq '####### stop instruction reached:' "$tmp/u64_emulator.log" || {
    cat "$tmp/u64_emulator.log" >&2
    echo "Rust CellSPU u64-addition image did not reach stop" >&2
    exit 1
}

actual=$(od -An -N352 -tx1 "$tmp/u64_mailbox" | tr -d '[:space:]')
[[ "$actual" == 00000001000000002345789affffffff00000000012334560204060890b0d0f08123456789abcdef02468acf13579bde91a2b3c4d5e6f78023456789abcdef00c4d5e6f78000000089abcdef00000000abcdef000000000080000000000000008123456789abcdef02468acf13579bde123456789abcdef09abcdef00000000097530eca86420000000000000000000068acf13579bde0008123456789abcdef4091a2b3c4d5e6f70102468acf13579b008123456789abcd0000000102468acf0000000081234567000000000081234500000000000000018123456789abcdef4091a2b3c4d5e6f700123456789abcde0007f6e5d4c3b2a10000091a2b3c4d5e8123456789abcdefc091a2b3c4d5e6f7ff02468acf13579bff8123456789abcdffffffff02468acfffffffff81234567ffffffffff812345ffffffffffffffff8123456789abcdefc091a2b3c4d5e6f70000091a2b3c4d5efffc091a2b3c4d5e ]] || {
    echo "Unexpected Rust CellSPU arithmetic/shift results: ${actual:-<empty>}" >&2
    exit 1
}

echo "rustc 1.99 CellSPU no_core integer arithmetic and shifts: GNU-matched native encodings; emulator checked 88 add, subtract, bitwise, logical, and arithmetic shift results and reached stop"

"$rustc" -Z unstable-options \
    --target="$target_short_calls" \
    --crate-type=lib --emit=obj -Cpanic=abort -Copt-level=1 \
    -Coverflow-checks=off \
    -o "$tmp/u64_multiply.o" "$root/experiments/rustc-cellspu/u64_multiply.rs"

multiply_disassembly=$("$spu_objdump" -dr "$tmp/u64_multiply.o")
for instruction in mpyu mpyh mpyhhu; do
    grep -Eq "${instruction}[[:space:]]+\\$" <<<"$multiply_disassembly" || {
        echo "Rust u64 multiplication object did not contain native SPU $instruction" >&2
        exit 1
    }
done

multiply_header=$("$spu_readelf" -h "$tmp/u64_multiply.o")
for expected in "Class:                             ELF32" \
    "Data:                              2's complement, big endian" \
    "Machine:                           SPU"; do
    grep -Fq "$expected" <<<"$multiply_header" || {
        echo "Unexpected Rust u64 multiplication object header; expected $expected" >&2
        exit 1
    }
done

"$spu_objdump" -d "$tmp/u64_multiply.o" | \
    awk '$6 ~ /^(mpyu|mpyh|mpyhhu)$/ { printf "%s %s %s %s\n", $6, $7, $8, $9 }' \
    >"$tmp/mpyhhu.s"
"$spu_as" -o "$tmp/mpyhhu-reference.o" "$tmp/mpyhhu.s"
reference=$("$spu_objdump" -d "$tmp/mpyhhu-reference.o" | \
    awk '$6 ~ /^(mpyu|mpyh|mpyhhu)$/ { print $2 $3 $4 $5 }')
actual=$("$spu_objdump" -d "$tmp/u64_multiply.o" | \
    awk '$6 ~ /^(mpyu|mpyh|mpyhhu)$/ { print $2 $3 $4 $5 }')
if [[ "$reference" != "$actual" ]]; then
    echo "LLVM multiply instruction encodings differ from GNU SPU binutils" >&2
    echo "SPU assembler: ${reference//$'\n'/ }" >&2
    echo "LLVM object:   ${actual//$'\n'/ }" >&2
    exit 1
fi

"$spu_as" -o "$tmp/u64_multiply_start.o" \
    "$root/experiments/rustc-cellspu/u64_multiply_start.s"
"$spu_ld" -Ttext=0 -e _start -o "$tmp/u64_multiply.elf" \
    "$tmp/u64_multiply_start.o" "$tmp/u64_multiply.o"

if ! (cd "$tmp" && ANERG_MBOX="$tmp/u64_multiply_mailbox" \
    timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" "$tmp/u64_multiply.elf") \
    >"$tmp/u64_multiply_emulator.log" 2>&1; then
    cat "$tmp/u64_multiply_emulator.log" >&2
    echo "Rust CellSPU u64 multiplication emulator run failed or timed out" >&2
    exit 1
fi
grep -Fq '####### stop instruction reached:' "$tmp/u64_multiply_emulator.log" || {
    cat "$tmp/u64_multiply_emulator.log" >&2
    echo "Rust CellSPU u64 multiplication image did not reach stop" >&2
    exit 1
}

mailbox_size=$(wc -c <"$tmp/u64_multiply_mailbox")
[[ "$mailbox_size" -eq 32 ]] || {
    echo "Expected eight u64 multiplication result words, got $mailbox_size bytes" >&2
    exit 1
}
actual=$(od -An -N32 -tx1 "$tmp/u64_multiply_mailbox" | tr -d '[:space:]')
[[ "$actual" == 0000000a00000008fffffffffffffffe2236d88fe5618cf08000000180000000 ]] || {
    echo "Unexpected Rust CellSPU u64 multiplication results: ${actual:-<empty>}" >&2
    exit 1
}

echo "rustc 1.99 CellSPU no_core u64 wrapping multiplication: GNU-matched multiply encodings; emulator checked four products and reached stop"

"$rustc" -Z unstable-options \
    --target="$target_short_calls" \
    --crate-type=lib --emit=obj -Cpanic=abort -Copt-level=1 \
    -o "$tmp/dense_match.o" "$root/experiments/rustc-cellspu/dense_match.rs"

dense_match_disassembly=$("$spu_objdump" -dr "$tmp/dense_match.o")
for instruction in clgti lqx rotqby; do
    grep -Eq "${instruction}[[:space:]]+\\$" <<<"$dense_match_disassembly" || {
        echo "Rust dense match object did not contain native SPU $instruction" >&2
        exit 1
    }
done
dense_match_relocations=$("$spu_readelf" -r "$tmp/dense_match.o")
grep -Fq 'R_SPU_ADDR18' <<<"$dense_match_relocations" || {
    echo "Rust dense match object is missing its lookup-table address relocation" >&2
    exit 1
}

"$spu_objdump" -d "$tmp/dense_match.o" | \
    awk '$6 ~ /^(clgti|lqx|rotqby)$/ { printf "%s %s %s %s\n", $6, $7, $8, $9 }' \
    >"$tmp/dense_match-encoding.s"
"$spu_as" -o "$tmp/dense_match-reference.o" "$tmp/dense_match-encoding.s"
reference=$("$spu_objdump" -d "$tmp/dense_match-reference.o" | \
    awk '$6 ~ /^(clgti|lqx|rotqby)$/ { print $2 $3 $4 $5 }')
actual_encoding=$("$spu_objdump" -d "$tmp/dense_match.o" | \
    awk '$6 ~ /^(clgti|lqx|rotqby)$/ { print $2 $3 $4 $5 }')
if [[ "$reference" != "$actual_encoding" ]]; then
    echo "LLVM dense match instruction encodings differ from GNU SPU binutils" >&2
    echo "SPU assembler: ${reference//$'\n'/ }" >&2
    echo "LLVM object:   ${actual_encoding//$'\n'/ }" >&2
    exit 1
fi

"$spu_as" -o "$tmp/dense_match_start.o" \
    "$root/experiments/rustc-cellspu/dense_match_start.s"
"$spu_ld" -Ttext=0 -e _start -o "$tmp/dense_match.elf" \
    "$tmp/dense_match_start.o" "$tmp/dense_match.o"

if ! (cd "$tmp" && ANERG_MBOX="$tmp/dense_match_mailbox" \
    timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" "$tmp/dense_match.elf") \
    >"$tmp/dense_match_emulator.log" 2>&1; then
    cat "$tmp/dense_match_emulator.log" >&2
    echo "Rust CellSPU dense match emulator run failed or timed out" >&2
    exit 1
fi
grep -Fq '####### stop instruction reached:' "$tmp/dense_match_emulator.log" || {
    cat "$tmp/dense_match_emulator.log" >&2
    echo "Rust CellSPU dense match image did not reach stop" >&2
    exit 1
}

mailbox_size=$(wc -c <"$tmp/dense_match_mailbox")
[[ "$mailbox_size" -eq 48 ]] || {
    echo "Expected twelve dense match result words, got $mailbox_size bytes" >&2
    exit 1
}
actual=$(od -An -N48 -tx1 "$tmp/dense_match_mailbox" | tr -d '[:space:]')
[[ "$actual" == 13579bdf2468ace00f0f55aafedcba9889abcdef87654321a55aa55a5aa55aa511223344c001d00d00000b0b00000b0b ]] || {
    echo "Unexpected Rust CellSPU dense match results: ${actual:-<empty>}" >&2
    exit 1
}

echo "rustc 1.99 CellSPU no_core dense match: GNU-matched clgti/lqx/rotqby encodings; emulator checked ten table arms and two fallback inputs and reached stop"

"$rustc" -Z unstable-options \
    --target="$target_short_calls" \
    --crate-type=lib --emit=obj -Cpanic=abort -Copt-level=1 \
    -Cllvm-args=-verify-machineinstrs \
    -o "$tmp/sparse_match.o" "$root/experiments/rustc-cellspu/sparse_match.rs"

sparse_match_disassembly=$("$spu_objdump" -dr "$tmp/sparse_match.o")
for instruction in cgti clgti ceqi ceq brnz brz lqx rotqby; do
    grep -Eq "${instruction}[[:space:]]+\\$" <<<"$sparse_match_disassembly" || {
        echo "Rust sparse match object did not contain native SPU $instruction" >&2
        exit 1
    }
done
sparse_match_relocations=$("$spu_readelf" -r "$tmp/sparse_match.o")
grep -Fq 'R_SPU_ADDR18' <<<"$sparse_match_relocations" || {
    echo "Rust sparse match object is missing its jump-table address relocation" >&2
    exit 1
}

"$spu_objdump" -d "$tmp/sparse_match.o" | \
    awk '$6 ~ /^(cgti|clgti|ceqi|ceq|lqx|rotqby)$/ { printf "%s %s %s %s\n", $6, $7, $8, $9 }' \
    >"$tmp/sparse_match-encoding.s"
"$spu_as" -o "$tmp/sparse_match-reference.o" "$tmp/sparse_match-encoding.s"
reference=$("$spu_objdump" -d "$tmp/sparse_match-reference.o" | \
    awk '$6 ~ /^(cgti|clgti|ceqi|ceq|lqx|rotqby)$/ { print $2 $3 $4 $5 }')
actual_encoding=$("$spu_objdump" -d "$tmp/sparse_match.o" | \
    awk '$6 ~ /^(cgti|clgti|ceqi|ceq|lqx|rotqby)$/ { print $2 $3 $4 $5 }')
if [[ "$reference" != "$actual_encoding" ]]; then
    echo "LLVM sparse match instruction encodings differ from GNU SPU binutils" >&2
    echo "SPU assembler: ${reference//$'\n'/ }" >&2
    echo "LLVM object:   ${actual_encoding//$'\n'/ }" >&2
    exit 1
fi

"$spu_as" -o "$tmp/sparse_match_start.o" \
    "$root/experiments/rustc-cellspu/sparse_match_start.s"
"$spu_ld" -Ttext=0 -e _start -o "$tmp/sparse_match.elf" \
    "$tmp/sparse_match_start.o" "$tmp/sparse_match.o"

if ! (cd "$tmp" && ANERG_MBOX="$tmp/sparse_match_mailbox" \
    timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" "$tmp/sparse_match.elf") \
    >"$tmp/sparse_match_emulator.log" 2>&1; then
    cat "$tmp/sparse_match_emulator.log" >&2
    echo "Rust CellSPU sparse match emulator run failed or timed out" >&2
    exit 1
fi
grep -Fq '####### stop instruction reached:' "$tmp/sparse_match_emulator.log" || {
    cat "$tmp/sparse_match_emulator.log" >&2
    echo "Rust CellSPU sparse match image did not reach stop" >&2
    exit 1
}

mailbox_size=$(wc -c <"$tmp/sparse_match_mailbox")
[[ "$mailbox_size" -eq 48 ]] || {
    echo "Expected twelve sparse match result words, got $mailbox_size bytes" >&2
    exit 1
}
actual=$(od -An -N48 -tx1 "$tmp/sparse_match_mailbox" | tr -d '[:space:]')
[[ "$actual" == 1111000022220000aaaa00003333000044440000555500006666000077770000aaaa0000aaaa0000aaaa0000aaaa0000 ]] || {
    echo "Unexpected Rust CellSPU sparse match results: ${actual:-<empty>}" >&2
    exit 1
}

echo "rustc 1.99 CellSPU no_core sparse match: GNU-matched compare and table encodings; emulator checked seven arms plus table and range fallbacks and reached stop"

"$rustc" -Z unstable-options \
    --target="$target_short_calls" \
    --crate-type=lib --emit=obj -Cpanic=abort -Copt-level=1 \
    -Coverflow-checks=off \
    -o "$tmp/indexed_memory.o" "$root/experiments/rustc-cellspu/indexed_memory.rs"

indexed_memory_disassembly=$("$spu_objdump" -dr "$tmp/indexed_memory.o")
for instruction in cwx lqx rotqby shufb stqx; do
    grep -Eq "${instruction}[[:space:]]+\\$" <<<"$indexed_memory_disassembly" || {
        echo "Rust indexed-memory object did not contain native SPU $instruction" >&2
        exit 1
    }
done

"$spu_objdump" -d "$tmp/indexed_memory.o" | \
    awk '$6 ~ /^(cwx|lqx|rotqby|shufb|stqx)$/ { printf "%s", $6; for (i = 7; i <= NF && $i !~ /^#/; i++) printf " %s", $i; print "" }' \
    >"$tmp/indexed_memory-encoding.s"
"$spu_as" -o "$tmp/indexed_memory-reference.o" \
    "$tmp/indexed_memory-encoding.s"
reference=$("$spu_objdump" -d "$tmp/indexed_memory-reference.o" | \
    awk '$6 ~ /^(cwx|lqx|rotqby|shufb|stqx)$/ { print $2 $3 $4 $5 }')
actual_encoding=$("$spu_objdump" -d "$tmp/indexed_memory.o" | \
    awk '$6 ~ /^(cwx|lqx|rotqby|shufb|stqx)$/ { print $2 $3 $4 $5 }')
if [[ "$reference" != "$actual_encoding" ]]; then
    echo "LLVM indexed-memory instruction encodings differ from GNU SPU binutils" >&2
    echo "SPU assembler: ${reference//$'\n'/ }" >&2
    echo "LLVM object:   ${actual_encoding//$'\n'/ }" >&2
    exit 1
fi

"$spu_as" -o "$tmp/indexed_memory_start.o" \
    "$root/experiments/rustc-cellspu/indexed_memory_start.s"
"$spu_ld" -Ttext=0 -e _start -o "$tmp/indexed_memory.elf" \
    "$tmp/indexed_memory_start.o" "$tmp/indexed_memory.o"

if ! (cd "$tmp" && ANERG_MBOX="$tmp/indexed_memory_mailbox" \
    timeout "${SPU_EMULATOR_TIMEOUT:-10s}" "$emulator" "$tmp/indexed_memory.elf") \
    >"$tmp/indexed_memory_emulator.log" 2>&1; then
    cat "$tmp/indexed_memory_emulator.log" >&2
    echo "Rust CellSPU indexed-memory emulator run failed or timed out" >&2
    exit 1
fi
grep -Fq '####### stop instruction reached:' "$tmp/indexed_memory_emulator.log" || {
    cat "$tmp/indexed_memory_emulator.log" >&2
    echo "Rust CellSPU indexed-memory image did not reach stop" >&2
    exit 1
}

mailbox_size=$(wc -c <"$tmp/indexed_memory_mailbox")
[[ "$mailbox_size" -eq 64 ]] || {
    echo "Expected sixteen indexed-memory result words, got $mailbox_size bytes" >&2
    exit 1
}
actual=$(od -An -N64 -tx1 "$tmp/indexed_memory_mailbox" | tr -d '[:space:]')
[[ "$actual" == 111111112222222233333333444444445555555566666666777777778888888811111111deadbeef33333333444444441234567866666666777777770badf00d ]] || {
    echo "Unexpected Rust CellSPU indexed-memory results: ${actual:-<empty>}" >&2
    exit 1
}

echo "rustc 1.99 CellSPU no_core indexed memory: GNU-matched cwx/lqx/rotqby/shufb/stqx encodings; emulator checked eight indexed loads and three stores with neighbor preservation"
