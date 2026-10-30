//===-- SPUMCFixups.h - CellSPU MC fixups ----------------------*- C++ -*-===//
//
// This file is distributed under the University of Illinois Open Source
// License. See LLVM-NCSA-LICENSE.txt for details.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_LIB_TARGET_CELLSPU_MCTARGETDESC_SPUMCFIXUPS_H
#define LLVM_LIB_TARGET_CELLSPU_MCTARGETDESC_SPUMCFIXUPS_H

#include "llvm/MC/MCFixup.h"

namespace llvm::SPU {

enum Fixups {
  fixup_spu_addr16 = FirstTargetFixupKind,
  fixup_spu_rel16,
  fixup_spu_addr18,
  fixup_spu_addr16_hi,
  fixup_spu_addr16_lo,
  NumTargetFixupKinds
};

// GNU's SPU ELF ABI relocation numbers (include/elf/spu.h).
enum ELFRelocations {
  R_SPU_ADDR16 = 2,
  R_SPU_ADDR16_HI = 3,
  R_SPU_ADDR16_LO = 4,
  R_SPU_ADDR18 = 5,
  R_SPU_ADDR32 = 6,
  R_SPU_REL16 = 7,
  R_SPU_REL32 = 13
};

} // namespace llvm::SPU

#endif
