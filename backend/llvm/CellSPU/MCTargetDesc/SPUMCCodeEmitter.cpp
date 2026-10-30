//===-- SPUMCCodeEmitter.cpp - CellSPU instruction encoder -----*- C++ -*-===//
//
// This file is distributed under the University of Illinois Open Source
// License. See LLVM-NCSA-LICENSE.txt for details.
//
//===----------------------------------------------------------------------===//

#include "SPUMCFixups.h"
#include "SPUMCTargetDesc.h"
#include "llvm/MC/MCCodeEmitter.h"
#include "llvm/MC/MCContext.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCFixup.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

namespace {

class SPUMCCodeEmitter final : public MCCodeEmitter {
  const MCInstrInfo &InstrInfo;
  const MCRegisterInfo &RegisterInfo;

  unsigned reg(const MCInst &MI, unsigned Index) const {
    if (Index >= MI.getNumOperands() || !MI.getOperand(Index).isReg())
      reportUnsupportedOperand(MI, Index);
    return RegisterInfo.getEncodingValue(MI.getOperand(Index).getReg());
  }

  uint32_t immediate(const MCInst &MI, unsigned Index, unsigned Width) const {
    if (Index >= MI.getNumOperands() || !MI.getOperand(Index).isImm())
      reportUnsupportedOperand(MI, Index);
    return static_cast<uint32_t>(MI.getOperand(Index).getImm()) &
           ((uint32_t{1} << Width) - 1);
  }

  uint32_t immediateOrFixup(const MCInst &MI, unsigned Index, unsigned Width,
                            MCFixupKind FixupKind, bool IsPCRel,
                            SmallVectorImpl<MCFixup> &Fixups) const {
    if (Index >= MI.getNumOperands())
      reportUnsupportedOperand(MI, Index);
    const MCOperand &Operand = MI.getOperand(Index);
    if (Operand.isImm())
      return static_cast<uint32_t>(Operand.getImm()) &
             ((uint32_t{1} << Width) - 1);
    if (Operand.isExpr()) {
      Fixups.push_back(MCFixup::create(0, Operand.getExpr(), FixupKind,
                                       IsPCRel));
      return 0;
    }
    reportUnsupportedOperand(MI, Index);
  }

  unsigned expressionOperand(const MCInst &MI) const {
    for (unsigned I = 0; I != MI.getNumOperands(); ++I)
      if (MI.getOperand(I).isExpr())
        return I;
    reportUnsupportedInst(MI);
  }

  uint32_t encode(const MCInst &MI,
                  SmallVectorImpl<MCFixup> &Fixups) const {
    StringRef Name = InstrInfo.getName(MI.getOpcode());

    // RR format: opcode, RB, RA, RT.
    auto RR = [&](uint32_t Base) {
      return Base | (reg(MI, 2) << 14) | (reg(MI, 1) << 7) | reg(MI, 0);
    };
    // RRR format: opcode, RT, RB, RA, RC.
    auto RRR = [&](uint32_t Base) {
      return Base | (reg(MI, 0) << 21) | (reg(MI, 2) << 14) |
             (reg(MI, 1) << 7) | reg(MI, 3);
    };
    // RI10/RI7 format: opcode, immediate, RA, RT.
    auto RI10 = [&](uint32_t Base, unsigned ImmIndex, unsigned RAIndex,
                    unsigned RTIndex, unsigned Width, unsigned Scale) {
      return Base | ((immediate(MI, ImmIndex, Width + Scale) >> Scale) << 14) |
             (reg(MI, RAIndex) << 7) | reg(MI, RTIndex);
    };
    auto RI7Neg = [&](uint32_t Base, unsigned ImmIndex, unsigned RAIndex,
                      unsigned RTIndex) {
      uint32_t Imm = (0u - immediate(MI, ImmIndex, 7)) & 0x7f;
      return Base | (Imm << 14) | (reg(MI, RAIndex) << 7) |
             reg(MI, RTIndex);
    };
    auto Branch16 = [&](uint32_t Base, unsigned TargetIndex,
                        unsigned RegIndex, bool HasReg) {
      uint32_t Word = Base;
      if (HasReg)
        Word |= reg(MI, RegIndex);
      Word |= immediateOrFixup(MI, TargetIndex, 16, SPU::fixup_spu_rel16,
                               true, Fixups)
              << 7;
      return Word;
    };

    if (Name == "Ar32" || Name == "Av16i8" || Name == "Av4i32")
      return RR(0x18000000);
    if (Name == "AIr32" || Name == "AIv4i32" || Name == "AIv4f32" ||
        Name == "AIf32")
      return RI10(0x1c000000, 2, 1, 0, 10, 0);
    if (Name.starts_with("ANDI"))
      return RI10(0x14000000, 2, 1, 0, 10, 0);
    if (Name == "ANDCr32")
      return RR(0x58200000);
    if (Name.starts_with("AND"))
      return RR(0x18200000);
    if (Name.starts_with("ORI"))
      return RI10(0x04000000, 2, 1, 0, 10, 0);
    if (Name.starts_with("OR"))
      return RR(0x08200000);
    if (Name.starts_with("XORI"))
      return RI10(0x44000000, 2, 1, 0, 10, 0);
    if (Name.starts_with("XOR"))
      return RR(0x48200000);
    if (Name.starts_with("LR"))
      return 0x04000000 | (reg(MI, 1) << 7) | reg(MI, 0);
    if (Name.starts_with("CEQH"))
      return RR(0x79000000);
    if (Name.starts_with("CEQ"))
      return RR(0x78000000);
    if (Name.starts_with("CGTH"))
      return RR(0x49000000);
    if (Name.starts_with("CGT"))
      return RR(0x48000000);
    if (Name.starts_with("CLGTH"))
      return RR(0x59000000);
    if (Name.starts_with("CLGT"))
      return RR(0x58000000);
    if (Name == "CLZr32")
      return 0x54a00000 | (reg(MI, 1) << 7) | reg(MI, 0);
    if (Name == "CNTBv4i32")
      return 0x56800000 | (reg(MI, 1) << 7) | reg(MI, 0);
    if (Name == "MPYHr32")
      return RR(0x78a00000);
    if (Name == "MPYUr32")
      return RR(0x79800000);
    if (Name == "CGr32" || Name == "CGr64" || Name == "CGv2i64" ||
        Name == "CGv4i32")
      return RR(0x18400000);
    if (Name == "ADDXr32" || Name == "ADDXr64" ||
        Name == "ADDXv2i64" || Name == "ADDXv4i32")
      return RR(0x68000000);
    if (Name == "BGr32" || Name == "BGr64" || Name == "BGv2i64" ||
        Name == "BGv4i32")
      return RR(0x08400000);
    if (Name == "SFXr32" || Name == "SFXr64" ||
        Name == "SFXv2i64" || Name == "SFXv4i32")
      return RR(0x68200000);
    if (Name == "SFIr32")
      return RI10(0x0c000000, 2, 1, 0, 10, 0);
    if (Name.starts_with("SF"))
      return RR(0x08000000);
    if (Name == "SHLr32")
      return RR(0x0b600000);
    if (Name == "ROTMr32")
      return RR(0x0b200000);
    if (Name == "ROTMAr32")
      return RR(0x0b400000);
    if (Name == "ROTr32")
      return RR(0x0b000000);
    if (Name.starts_with("SHLI"))
      return RI10(0x0f600000, 2, 1, 0, 7, 0);
    if (Name.starts_with("ROTMAI"))
      return RI7Neg(0x0f400000, 2, 1, 0);
    if (Name.starts_with("ROTMI"))
      return RI7Neg(0x0f200000, 2, 1, 0);
    if (Name.starts_with("ROTQBY"))
      return RR(0x3b800000);
    if (Name.starts_with("SHUFB"))
      return RRR(0xb0000000);

    if (Name == "RET")
      return 0x35000000;
    if (Name == "BI")
      return 0x35000000 | (reg(MI, 0) << 7);
    if (Name == "BR")
      return Branch16(0x32000000, expressionOperand(MI), 0, false);
    if (Name == "BRSL")
      return Branch16(0x33000000, expressionOperand(MI), 0, false);
    if (Name.starts_with("BRHNZ"))
      return Branch16(0x23000000, expressionOperand(MI), 0, true);
    if (Name.starts_with("BRHZ"))
      return Branch16(0x22000000, expressionOperand(MI), 0, true);
    if (Name.starts_with("BRNZ"))
      return Branch16(0x21000000, expressionOperand(MI), 0, true);
    if (Name.starts_with("BRZ"))
      return Branch16(0x20000000, expressionOperand(MI), 0, true);

    if (Name == "CHD")
      return RI10(0x3ea00000, 1, 2, 0, 7, 0);
    if (Name.starts_with("CWD"))
      return RI10(0x3ec00000, 1, 2, 0, 7, 0);
    if (Name.starts_with("ILA"))
      return 0x42000000 | (immediate(MI, 1, 18) << 7) | reg(MI, 0);
    if (Name.starts_with("ILHU"))
      return (0x41000000 | (immediate(MI, 1, 16) << 7) | reg(MI, 0));
    if (Name.starts_with("IL"))
      return (0x40800000 | (immediate(MI, 1, 16) << 7) | reg(MI, 0));
    if (Name == "LNOP" || Name == "HBRA")
      // Branch hints do not change program semantics. Preserve their slot as
      // an SPU load-pipeline no-op until their two target fixups are modeled.
      return 0x00200000;
    if (Name == "ENOP")
      return 0x40200000;
    if (Name.starts_with("LQA")) {
      unsigned Target = expressionOperand(MI);
      uint32_t Offset = immediateOrFixup(MI, Target, 16,
                                         SPU::fixup_spu_addr16, false, Fixups);
      return 0x30800000 | (Offset << 7) | reg(MI, 0);
    }
    if (Name.starts_with("LQD"))
      return RI10(0x34000000, 1, 2, 0, 10, 4);
    if (Name.starts_with("STQD"))
      return RI10(0x24000000, 1, 2, 0, 10, 4);

    reportUnsupportedInst(MI);
  }

public:
  SPUMCCodeEmitter(const MCInstrInfo &II, const MCRegisterInfo &MRI)
      : InstrInfo(II), RegisterInfo(MRI) {}

  void encodeInstruction(const MCInst &MI, SmallVectorImpl<char> &Bytes,
                         SmallVectorImpl<MCFixup> &Fixups,
                         const MCSubtargetInfo & /*STI*/) const override {
    uint32_t Word = encode(MI, Fixups);
    Bytes.push_back(static_cast<char>(Word >> 24));
    Bytes.push_back(static_cast<char>(Word >> 16));
    Bytes.push_back(static_cast<char>(Word >> 8));
    Bytes.push_back(static_cast<char>(Word));
  }
};

} // namespace

MCCodeEmitter *llvm::createSPUMCCodeEmitter(const MCInstrInfo &II,
                                            MCContext &Ctx) {
  return new SPUMCCodeEmitter(II, *Ctx.getRegisterInfo());
}
