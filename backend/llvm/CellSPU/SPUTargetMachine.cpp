//===-- SPUTargetMachine.cpp - Cell SPU target machine --------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#include "SPUTargetMachine.h"
#include "SPU.h"
#include "llvm/CodeGen/Passes.h"
#include "llvm/CodeGen/TargetLoweringObjectFileImpl.h"
#include "llvm/CodeGen/TargetPassConfig.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/CodeGen.h"
#include "llvm/Support/ErrorHandling.h"

using namespace llvm;

static Reloc::Model getEffectiveRelocModel(std::optional<Reloc::Model> RM) {
  return RM.value_or(Reloc::Static);
}

SPUTargetMachine::SPUTargetMachine(const Target &T, const Triple &TT,
                                   StringRef CPU, StringRef FS,
                                   const TargetOptions &Options,
                                   std::optional<Reloc::Model> RM,
                                   std::optional<CodeModel::Model> CM,
                                   CodeGenOptLevel OL, bool JIT)
    : CodeGenTargetMachineImpl(
          T, SPUSubtarget::getDataLayoutString(), TT, CPU, FS, Options,
          getEffectiveRelocModel(RM),
          getEffectiveCodeModel(CM, CodeModel::Small), OL),
      Subtarget(TT, CPU.str(), FS.str(), *this),
      TLOF(std::make_unique<TargetLoweringObjectFileELF>()) {
  if (JIT)
    report_fatal_error("Cell SPU JIT is unsupported");
  initAsmInfo();
}

namespace {
class SPUPassConfig : public TargetPassConfig {
public:
  SPUPassConfig(SPUTargetMachine &TM, PassManagerBase &PM)
      : TargetPassConfig(TM, PM) {}

  SPUTargetMachine &getSPUTargetMachine() const {
    return getTM<SPUTargetMachine>();
  }

  bool addInstSelector() override;
  void addPreEmitPass() override;
};
} // namespace

TargetPassConfig *SPUTargetMachine::createPassConfig(PassManagerBase &PM) {
  return new SPUPassConfig(*this, PM);
}

bool SPUPassConfig::addInstSelector() {
  addPass(createSPUISelDag(getSPUTargetMachine()));
  return false;
}

void SPUPassConfig::addPreEmitPass() {
  addPass(createSPUNopFillerPass(getSPUTargetMachine()));
}

extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void
LLVMInitializeCellSPUTarget() {
  RegisterTargetMachine<SPUTargetMachine> X(TheCellSPUTarget);
}
