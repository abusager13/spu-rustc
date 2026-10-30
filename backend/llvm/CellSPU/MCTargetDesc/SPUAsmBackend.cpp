//===-- SPUAsmBackend.cpp - CellSPU assembler backend -----------*- C++ -*-===//
//
// This file is distributed under the University of Illinois Open Source
// License. See LLVM-NCSA-LICENSE.txt for details.
//
//===----------------------------------------------------------------------===//

#include "SPUMCFixups.h"
#include "SPUMCTargetDesc.h"
#include "llvm/MC/MCAsmBackend.h"
#include "llvm/MC/MCAssembler.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCObjectWriter.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/Endian.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"
#include <cstdint>

using namespace llvm;

namespace {

class SPUAsmBackend final : public MCAsmBackend {
public:
  SPUAsmBackend() : MCAsmBackend(endianness::big) {}

  MCFixupKindInfo getFixupKindInfo(MCFixupKind Kind) const override {
    static const MCFixupKindInfo Infos[SPU::NumTargetFixupKinds -
                                       FirstTargetFixupKind] = {
        {"fixup_spu_addr16", 7, 16, 0},
        {"fixup_spu_rel16", 7, 16, 0},
        {"fixup_spu_addr18", 7, 18, 0},
        {"fixup_spu_addr16_hi", 7, 16, 0},
        {"fixup_spu_addr16_lo", 7, 16, 0},
        {"fixup_spu_hbra", 0, 9, 0},
    };
    if (Kind < FirstTargetFixupKind)
      return MCAsmBackend::getFixupKindInfo(Kind);
    unsigned Index = Kind - FirstTargetFixupKind;
    assert(Index < SPU::NumTargetFixupKinds - FirstTargetFixupKind &&
           "invalid CellSPU fixup kind");
    return Infos[Index];
  }

  void applyFixup(const MCFragment &Fragment, const MCFixup &Fixup,
                  const MCValue &Target, uint8_t *Data, uint64_t Value,
                  bool IsResolved) override {
    if (Fixup.getKind() == SPU::fixup_spu_hbra && !IsResolved)
      report_fatal_error(
          "CellSPU HBRA branch instruction address must resolve locally");
    maybeAddReloc(Fragment, Fixup, Target, Value, IsResolved);
    if (!IsResolved)
      return;

    if (Fixup.getKind() != SPU::fixup_spu_addr16 &&
        Fixup.getKind() != SPU::fixup_spu_rel16 &&
        Fixup.getKind() != SPU::fixup_spu_addr18 &&
        Fixup.getKind() != SPU::fixup_spu_addr16_hi &&
        Fixup.getKind() != SPU::fixup_spu_addr16_lo &&
        Fixup.getKind() != SPU::fixup_spu_hbra &&
        Fixup.getKind() != FK_Data_4)
      report_fatal_error("unsupported CellSPU fixup kind");

    // MCAsmBackend passes Data at the fixup location, not at the fragment
    // start (see MCAsmBackend::applyFixup's contract).
    uint8_t *Location = Data;
    if (Fixup.getKind() == FK_Data_4) {
      support::endian::write32be(Location, static_cast<uint32_t>(Value));
      return;
    }

    if (Fixup.getKind() == SPU::fixup_spu_hbra) {
      uint32_t BranchWordAddress =
          (static_cast<uint32_t>(Value >> 2)) & 0x1ffU;
      uint32_t Word = support::endian::read32be(Location);
      Word = (Word & ~0x0180007fU) | (BranchWordAddress & 0x7fU) |
             ((BranchWordAddress & 0x180U) << 16);
      support::endian::write32be(Location, Word);
      return;
    }

    if (Fixup.getKind() == SPU::fixup_spu_addr18) {
      if (Value > 0x3ffff)
        getContext().reportError(Fixup.getLoc(),
                                 "CellSPU address does not fit in 18 bits");
      uint32_t Word = support::endian::read32be(Location);
      Word = (Word & ~0x01ffff80U) |
             ((static_cast<uint32_t>(Value) & 0x3ffffU) << 7);
      support::endian::write32be(Location, Word);
      return;
    }

    if (Fixup.getKind() == SPU::fixup_spu_addr16_hi ||
        Fixup.getKind() == SPU::fixup_spu_addr16_lo) {
      uint64_t EncodedValue =
          Fixup.getKind() == SPU::fixup_spu_addr16_hi ? Value >> 16 : Value;
      uint32_t Word = support::endian::read32be(Location);
      Word = (Word & ~0x007fff80U) |
             ((static_cast<uint32_t>(EncodedValue) & 0xffffU) << 7);
      support::endian::write32be(Location, Word);
      return;
    }

    if ((Value & 3) != 0)
      getContext().reportError(Fixup.getLoc(),
                               "CellSPU branch/address fixup is not word aligned");
    if (Fixup.getKind() == SPU::fixup_spu_rel16) {
      int64_t SignedValue = static_cast<int64_t>(Value);
      if (SignedValue > (INT16_MAX * 4LL) ||
          SignedValue < (INT16_MIN * 4LL))
        getContext().reportError(Fixup.getLoc(),
                                 "CellSPU branch target is out of range");
    }

    uint32_t Word = support::endian::read32be(Location);
    uint32_t Encoded = static_cast<uint32_t>(Value >> 2) & 0xffff;
    Word = (Word & ~0x007fff80U) | (Encoded << 7);
    support::endian::write32be(Location, Word);
  }

  std::unique_ptr<MCObjectTargetWriter>
  createObjectTargetWriter() const override;

  bool writeNopData(raw_ostream &OS, uint64_t Count,
                    const MCSubtargetInfo * /*STI*/) const override {
    if ((Count & 3) != 0)
      return false;
    static constexpr char Nop[] = {0x40, 0x20, 0x00, 0x00};
    for (uint64_t I = 0; I != Count; I += sizeof(Nop))
      OS.write(Nop, sizeof(Nop));
    return true;
  }
};

} // namespace

std::unique_ptr<MCObjectTargetWriter>
SPUAsmBackend::createObjectTargetWriter() const {
  return llvm::createSPUELFObjectWriter();
}

MCAsmBackend *llvm::createSPUAsmBackend(const Target & /*T*/,
                                        const MCSubtargetInfo & /*STI*/,
                                        const MCRegisterInfo & /*MRI*/,
                                        const MCTargetOptions & /*Options*/) {
  return new SPUAsmBackend();
}
