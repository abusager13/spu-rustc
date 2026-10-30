#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
llvm_source=${1:?usage: test-llvm-cellspu-tablegen.sh LLVM_PROJECT_SOURCE [BUILD_DIR]}
build_dir=${2:-${TMPDIR:-/tmp}/spu-rustc-llvm23-tablegen}
expected_commit=6dfe1677ab8dffbc6ec13d53a1e0215d75147689

if [[ ! -f "$llvm_source/llvm/CMakeLists.txt" ]]; then
    echo "LLVM_SOURCE must point to the llvm-project source root" >&2
    exit 2
fi
actual_commit=$(git -C "$llvm_source" rev-parse HEAD)
if [[ "$actual_commit" != "$expected_commit" ]]; then
    echo "expected llvmorg-23.1.1 commit $expected_commit, found $actual_commit" >&2
    exit 2
fi

target_dir="$llvm_source/llvm/lib/Target/CellSPU"
if [[ -e "$target_dir" ]]; then
    echo "refusing to overwrite existing target directory: $target_dir" >&2
    exit 2
fi

git -C "$llvm_source" apply --check --unidiff-zero \
    "$root/backend/llvm/patches/llvm-23.1.1-cellspu-triple.patch"
git -C "$llvm_source" apply --unidiff-zero \
    "$root/backend/llvm/patches/llvm-23.1.1-cellspu-triple.patch"

python3 - "$llvm_source/llvm/CMakeLists.txt" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
source = path.read_text()
needle = "  BPF\n  Hexagon\n"
if source.count(needle) != 1 or "  CellSPU\n" in source:
    raise SystemExit("LLVM target list does not match the pinned source layout")
path.write_text(source.replace(needle, "  BPF\n  CellSPU\n  Hexagon\n", 1))
PY

cp -a "$root/backend/llvm/CellSPU" "$target_dir"

cmake -S "$llvm_source/llvm" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DLLVM_TARGETS_TO_BUILD='CellSPU;X86' \
    -DLLVM_TARGET_ARCH=x86_64 \
    -DLLVM_BUILD_TOOLS=ON \
    -DLLVM_BUILD_UTILS=ON \
    -DLLVM_INCLUDE_TESTS=OFF \
    -DLLVM_INCLUDE_EXAMPLES=OFF \
    -DLLVM_ENABLE_PROJECTS= \
    -DCMAKE_INSTALL_PREFIX="$build_dir/install"
ninja -C "$build_dir" CellSPUCommonTableGen
echo "CellSPU TableGen generation passed for LLVM 23.1.1"
