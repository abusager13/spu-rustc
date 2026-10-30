//===-- SPUInstPrinter.cpp - Print Cell SPU MC instructions ---------------===//
//
// This file is derived from LLVM's historical CellSPU backend and is
// distributed under the license in LLVM-NCSA-LICENSE.txt.
//
//===----------------------------------------------------------------------===//

#include "SPUInstPrinter.h"
#include "llvm/MC/MCAsmInfo.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/Support/ErrorHandling.h"
#include <cassert>
#include <cstdint>

using namespace llvm;

#define PRINT_ALIAS_INSTR
#include "SPUGenAsmWriter.inc"

void SPUInstPrinter::printRegName(raw_ostream &OS, MCRegister Reg) {
  OS << getRegisterName(Reg);
}

void SPUInstPrinter::PrintSpecial(const MCInst * /*MI*/, raw_ostream & /*OS*/,
                                  const char *Code) {
  if (StringRef(Code) != "comment")
    llvm_unreachable("unsupported CellSPU TableGen print modifier");
}

void SPUInstPrinter::printInst(const MCInst *MI, uint64_t Address,
                               StringRef Annotation,
                               const MCSubtargetInfo & /*STI*/,
                               raw_ostream &OS) {
  if (!printAliasInstr(MI, Address, OS))
    printInstruction(MI, Address, OS);
  printAnnotation(OS, Annotation);
}

void SPUInstPrinter::printOperand(const MCInst *MI, unsigned OpNo,
                                  raw_ostream &OS) {
  const MCOperand &Op = MI->getOperand(OpNo);
  if (Op.isReg()) {
    printRegName(OS, Op.getReg());
  } else if (Op.isImm()) {
    OS << Op.getImm();
  } else if (Op.isExpr()) {
    MAI.printExpr(OS, *Op.getExpr());
  } else {
    llvm_unreachable("unsupported CellSPU MC operand");
  }
}

void SPUInstPrinter::printU7ImmOperand(const MCInst *MI, unsigned OpNo,
                                      raw_ostream &OS) {
  const int64_t Value = MI->getOperand(OpNo).getImm();
  assert(Value >= 0 && Value < (1 << 7) && "invalid u7 operand");
  OS << Value;
}

void SPUInstPrinter::printS10ImmOperand(const MCInst *MI, unsigned OpNo,
                                        raw_ostream &OS) {
  OS << static_cast<int16_t>(MI->getOperand(OpNo).getImm());
}

void SPUInstPrinter::printU10ImmOperand(const MCInst *MI, unsigned OpNo,
                                        raw_ostream &OS) {
  const uint64_t Value = MI->getOperand(OpNo).getImm();
  assert(Value <= 0x3ff && "invalid u10 operand");
  OS << Value;
}

void SPUInstPrinter::printS16ImmOperand(const MCInst *MI, unsigned OpNo,
                                        raw_ostream &OS) {
  OS << static_cast<int16_t>(MI->getOperand(OpNo).getImm());
}

void SPUInstPrinter::printU16ImmOperand(const MCInst *MI, unsigned OpNo,
                                        raw_ostream &OS) {
  OS << static_cast<uint16_t>(MI->getOperand(OpNo).getImm());
}

void SPUInstPrinter::printU18ImmOperand(const MCInst *MI, unsigned OpNo,
                                        raw_ostream &OS) {
  const uint64_t Value = MI->getOperand(OpNo).getImm();
  assert(Value < (1 << 18) && "invalid u18 operand");
  OS << Value;
}

void SPUInstPrinter::printShufAddr(const MCInst *MI, unsigned OpNo,
                                   raw_ostream &OS) {
  printOperand(MI, OpNo, OS);
  OS << '(';
  printOperand(MI, OpNo + 1, OS);
  OS << ')';
}

void SPUInstPrinter::printMemRegReg(const MCInst *MI, unsigned OpNo,
                                    raw_ostream &OS) {
  printOperand(MI, OpNo, OS);
  OS << ", ";
  printOperand(MI, OpNo + 1, OS);
}

void SPUInstPrinter::printDFormAddr(const MCInst *MI, unsigned OpNo,
                                    raw_ostream &OS) {
  const MCOperand &Offset = MI->getOperand(OpNo);
  assert(Offset.isImm() && "d-form offset must be immediate");
  const int16_t Value = static_cast<int16_t>(Offset.getImm());
  assert(Value >= -(1 << 13) && Value <= (1 << 13) - 1 &&
         "invalid d-form offset");
  OS << (Value & ~0xf) << '(';
  printOperand(MI, OpNo + 1, OS);
  OS << ')';
}

void SPUInstPrinter::printAddr256K(const MCInst *MI, unsigned OpNo,
                                   raw_ostream &OS) {
  const MCOperand &Address = MI->getOperand(OpNo);
  if (Address.isImm()) {
    printS16ImmOperand(MI, OpNo, OS);
    return;
  }
  printOperand(MI, OpNo, OS);
  if (MI->getOperand(OpNo + 1).isImm()) {
    const int64_t Offset = MI->getOperand(OpNo + 1).getImm();
    if (Offset > 0)
      OS << '+' << Offset;
    else if (Offset < 0)
      OS << Offset;
  }
}

void SPUInstPrinter::printCallOperand(const MCInst *MI, unsigned OpNo,
                                      raw_ostream &OS) {
  printOperand(MI, OpNo, OS);
}

void SPUInstPrinter::printHBROperand(const MCInst *MI, unsigned OpNo,
                                     raw_ostream &OS) {
  printOperand(MI, OpNo, OS);
}

void SPUInstPrinter::printPCRelativeOperand(const MCInst *MI, unsigned OpNo,
                                            raw_ostream &OS) {
  printOperand(MI, OpNo, OS);
}

void SPUInstPrinter::printSymbolHi(const MCInst *MI, unsigned OpNo,
                                   raw_ostream &OS) {
  printOperand(MI, OpNo, OS);
  OS << "@h";
}

void SPUInstPrinter::printSymbolLo(const MCInst *MI, unsigned OpNo,
                                   raw_ostream &OS) {
  printOperand(MI, OpNo, OS);
  OS << "@l";
}

void SPUInstPrinter::printSymbolLSA(const MCInst *MI, unsigned OpNo,
                                    raw_ostream &OS) {
  printOperand(MI, OpNo, OS);
}

void SPUInstPrinter::printROTHNeg7Imm(const MCInst *MI, unsigned OpNo,
                                      raw_ostream &OS) {
  const int64_t Value = MI->getOperand(OpNo).getImm();
  assert(Value >= 0 && Value < 16 && "invalid negated rotate halfword");
  OS << -Value;
}

void SPUInstPrinter::printROTNeg7Imm(const MCInst *MI, unsigned OpNo,
                                     raw_ostream &OS) {
  const int64_t Value = MI->getOperand(OpNo).getImm();
  assert(Value >= 0 && Value <= 32 && "invalid negated rotate word");
  OS << -Value;
}
