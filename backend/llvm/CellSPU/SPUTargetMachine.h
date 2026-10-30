//===-- SPUTargetMachine.h - Cell SPU target machine ------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#ifndef SPU_TARGETMACHINE_H
#define SPU_TARGETMACHINE_H

#include "SPUSubtarget.h"
#include "llvm/CodeGen/CodeGenTargetMachineImpl.h"

#include <memory>
#include <optional>

namespace llvm {

class SPUTargetMachine : public CodeGenTargetMachineImpl {
  SPUSubtarget Subtarget;
  std::unique_ptr<TargetLoweringObjectFile> TLOF;

public:
  SPUTargetMachine(const Target &T, const Triple &TT, StringRef CPU,
                   StringRef FS, const TargetOptions &Options,
                   std::optional<Reloc::Model> RM,
                   std::optional<CodeModel::Model> CM, CodeGenOptLevel OL,
                   bool JIT);

  const SPUSubtarget *getSubtargetImpl() const { return &Subtarget; }
  const SPUSubtarget *getSubtargetImpl(const Function &) const override {
    return &Subtarget;
  }

  TargetLoweringObjectFile *getObjFileLowering() const override {
    return TLOF.get();
  }

  MachineFunctionInfo *createMachineFunctionInfo(
      BumpPtrAllocator &Allocator, const Function &F,
      const TargetSubtargetInfo *STI) const override;

  TargetPassConfig *createPassConfig(PassManagerBase &PM) override;
};

} // namespace llvm

#endif
