//===-- SPUAsmPrinter.cpp - Emit Cell SPU assembly -----------------------===//
//
// This file is derived from LLVM's historical CellSPU backend and is
// distributed under the license in LLVM-NCSA-LICENSE.txt.
//
//===----------------------------------------------------------------------===//

#include "SPU.h"
#include "SPUTargetMachine.h"
#include "llvm/CodeGen/AsmPrinter.h"
#include "llvm/CodeGen/MachineInstr.h"
#include "llvm/MC/MCExpr.h"
#include "llvm/MC/MCInst.h"
#include "llvm/MC/MCStreamer.h"
#include "llvm/MC/MCSymbol.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

namespace {

const MCExpr *createSymbolExpr(MCSymbol *Symbol, int64_t Offset,
                               MCContext &Context) {
  const MCExpr *Expr = MCSymbolRefExpr::create(Symbol, Context);
  if (Offset != 0)
    Expr = MCBinaryExpr::createAdd(
        Expr, MCConstantExpr::create(Offset, Context), Context);
  return Expr;
}

class SPUAsmPrinter final : public AsmPrinter {
public:
  SPUAsmPrinter(TargetMachine &TM, std::unique_ptr<MCStreamer> Streamer)
      : AsmPrinter(TM, std::move(Streamer)) {}

  StringRef getPassName() const override { return "Cell SPU Assembly Printer"; }

  void emitInstruction(const MachineInstr *MI) override {
    if (MI->getOpcode() == SPU::HBR_LABEL) {
      if (MI->getNumOperands() == 0 || !MI->getOperand(0).isMCSymbol()) {
        MI->print(errs());
        report_fatal_error("malformed CellSPU branch-hint label");
      }
      OutStreamer->emitLabel(MI->getOperand(0).getMCSymbol());
      return;
    }

    MCInst OutMI;
    OutMI.setOpcode(MI->getOpcode());

    for (const MachineOperand &MO : MI->operands()) {
      MCOperand OutOp;
      switch (MO.getType()) {
      case MachineOperand::MO_Register:
        if (MO.isImplicit())
          continue;
        OutOp = MCOperand::createReg(MO.getReg());
        break;
      case MachineOperand::MO_Immediate:
        OutOp = MCOperand::createImm(MO.getImm());
        break;
      case MachineOperand::MO_MachineBasicBlock:
        OutOp = MCOperand::createExpr(MCSymbolRefExpr::create(
            MO.getMBB()->getSymbol(), OutContext));
        break;
      case MachineOperand::MO_GlobalAddress:
        OutOp = MCOperand::createExpr(createSymbolExpr(
            getSymbol(MO.getGlobal()), MO.getOffset(), OutContext));
        break;
      case MachineOperand::MO_BlockAddress:
        OutOp = MCOperand::createExpr(createSymbolExpr(
            GetBlockAddressSymbol(MO.getBlockAddress()), MO.getOffset(),
            OutContext));
        break;
      case MachineOperand::MO_ExternalSymbol:
        OutOp = MCOperand::createExpr(createSymbolExpr(
            GetExternalSymbolSymbol(MO.getSymbolName()), MO.getOffset(),
            OutContext));
        break;
      case MachineOperand::MO_JumpTableIndex:
        OutOp = MCOperand::createExpr(MCSymbolRefExpr::create(
            GetJTISymbol(MO.getIndex()), OutContext));
        break;
      case MachineOperand::MO_ConstantPoolIndex:
        OutOp = MCOperand::createExpr(createSymbolExpr(
            GetCPISymbol(MO.getIndex()), MO.getOffset(), OutContext));
        break;
      case MachineOperand::MO_MCSymbol:
        OutOp = MCOperand::createExpr(MCSymbolRefExpr::create(
            MO.getMCSymbol(), OutContext));
        break;
      case MachineOperand::MO_RegisterMask:
        continue;
      default:
        MI->print(errs());
        report_fatal_error("unsupported CellSPU machine operand in assembly printer");
      }

      if (MO.getTargetFlags() != 0)
        report_fatal_error("CellSPU assembly printer does not support target operand flags");
      OutMI.addOperand(OutOp);
    }

    OutStreamer->emitInstruction(OutMI, getSubtargetInfo());
  }
};

} // namespace

extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void
LLVMInitializeCellSPUAsmPrinter() {
  RegisterAsmPrinter<SPUAsmPrinter> X(TheCellSPUTarget);
}
