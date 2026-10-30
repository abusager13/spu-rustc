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

"$rustc" -Z unstable-options \
    --target="$root/experiments/rustc-cellspu/target.json" \
    --crate-type=lib --emit=obj -Cpanic=abort -Copt-level=1 \
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
    --target="$root/experiments/rustc-cellspu/target.json" \
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

cat >"$tmp/carry-encoding.s" <<'ASM'
.text
cg $5,$4,$3
addx $5,$4,$3
and $3,$4,$3
iohl $4,0x0607
ASM
cat >>"$tmp/carry-encoding.s" <<'ASM'
bg $5,$4,$3
sfx $5,$4,$3
ASM
"$spu_as" -o "$tmp/carry-encoding.o" "$tmp/carry-encoding.s"
reference=$("$spu_objdump" -d "$tmp/carry-encoding.o" | \
    awk '$6 == "cg" || $6 == "addx" || $6 == "and" || $6 == "bg" || $6 == "sfx" || $6 == "iohl" { print $2 $3 $4 $5 }')
actual_encoding=$("$spu_objdump" -d "$tmp/u64_arithmetic.o" | \
    awk '$6 == "cg" || $6 == "addx" || $6 == "and" || $6 == "bg" || $6 == "sfx" || $6 == "iohl" { print $2 $3 $4 $5 }')
if [[ "$reference" != "$actual_encoding" ]]; then
    echo "LLVM arithmetic/logic instruction encodings differ from SPU GNU binutils" >&2
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

actual=$(od -An -N32 -tx1 "$tmp/u64_mailbox" | tr -d '[:space:]')
[[ "$actual" == 00000001000000002345789affffffff00000000012334560204060890b0d0f0 ]] || {
    echo "Unexpected Rust u64 arithmetic results: ${actual:-<empty>}" >&2
    exit 1
}

echo "rustc 1.99 CellSPU no_core u64 arithmetic: GNU-matched native encodings; emulator checked add, subtract, and bitwise results and reached stop"
