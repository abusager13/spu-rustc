#!/usr/bin/env bash
set -euo pipefail

real_config=${CELLSPU_REAL_LLVM_CONFIG:?set CELLSPU_REAL_LLVM_CONFIG to the custom llvm-config path}

if [[ $# -eq 1 && $1 == --components ]]; then
    "$real_config" "$@" | awk '{
        for (i = 1; i <= NF; i++) {
            if ($i == "cellspu") {
                $i = "powerpc"
            }
        }
        print
    }'
    exit 0
fi

args=()
for arg in "$@"; do
    if [[ $arg == powerpc ]]; then
        args+=(cellspu)
    else
        args+=("$arg")
    fi
done

exec "$real_config" "${args[@]}"
