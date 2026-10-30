//===-- SPUELFObjectWriter.cpp - CellSPU ELF writer ------------*- C++ -*-===//
//
// This file is distributed under the University of Illinois Open Source
// License. See LLVM-NCSA-LICENSE.txt for details.
//
//===----------------------------------------------------------------------===//

#include "SPUMCFixups.h"
#include "SPUMCTargetDesc.h"
#include "llvm/BinaryFormat/ELF.h"
#include "llvm/MC/MCELFObjectWriter.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCValue.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

namespace {

class SPUELFObjectWriter final : public MCELFObjectTargetWriter {
public:
  SPUELFObjectWriter()
      : MCELFObjectTargetWriter(/*Is64Bit=*/false, ELF::ELFOSABI_NONE,
                                ELF::EM_SPU,
                                /*HasRelocationAddend=*/true) {}

  unsigned getRelocType(const MCFixup &Fixup, const MCValue &,
                        bool IsPCRel) const override {
    switch (Fixup.getKind()) {
    case SPU::fixup_spu_addr16:
      return SPU::R_SPU_ADDR16;
    case SPU::fixup_spu_rel16:
      return SPU::R_SPU_REL16;
    case FK_Data_4:
      return IsPCRel ? 13 /* R_SPU_REL32 */ : SPU::R_SPU_ADDR32;
    default:
      llvm_unreachable("unsupported CellSPU ELF relocation");
    }
  }
};

} // namespace

std::unique_ptr<MCObjectTargetWriter> llvm::createSPUELFObjectWriter() {
  return std::make_unique<SPUELFObjectWriter>();
}
