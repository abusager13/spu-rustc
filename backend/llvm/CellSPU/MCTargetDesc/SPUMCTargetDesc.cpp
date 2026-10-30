//===-- SPUMCTargetDesc.cpp - Cell SPU target descriptions ----------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#include "SPUMCTargetDesc.h"
#include "SPUMCAsmInfo.h"
#include "SPUMCFixups.h"
#include "SPUInstPrinter.h"
#include "llvm/MC/MCAsmBackend.h"
#include "llvm/MC/MCCodeEmitter.h"
#include "llvm/MC/MCInstrInfo.h"
#include "llvm/MC/MCRegisterInfo.h"
#include "llvm/MC/MCSubtargetInfo.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/TargetParser/Triple.h"

#define GET_INSTRINFO_MC_DESC
#include "SPUGenInstrInfo.inc"

#define GET_SUBTARGETINFO_MC_DESC
#include "SPUGenSubtargetInfo.inc"

#define GET_REGINFO_MC_DESC
#include "SPUGenRegisterInfo.inc"

using namespace llvm;

static MCInstrInfo *createSPUMCInstrInfo() {
  auto *Info = new MCInstrInfo();
  InitSPUMCInstrInfo(Info);
  return Info;
}

static MCRegisterInfo *createSPUMCRegisterInfo(const Triple &TT) {
  auto *Info = new MCRegisterInfo();
  InitSPUMCRegisterInfo(Info, SPU::R0);
  return Info;
}

static MCSubtargetInfo *createSPUMCSubtargetInfo(const Triple &TT,
                                                StringRef CPU, StringRef FS) {
  return createSPUMCSubtargetInfoImpl(TT, CPU, CPU, FS);
}

static MCInstPrinter *createSPUMCInstPrinter(const Triple & /*TT*/,
                                             unsigned SyntaxVariant,
                                             const MCAsmInfo &MAI,
                                             const MCInstrInfo &MII,
                                             const MCRegisterInfo &MRI) {
  if (SyntaxVariant != 0)
    return nullptr;
  return new SPUInstPrinter(MAI, MII, MRI);
}

extern "C" LLVM_ABI LLVM_EXTERNAL_VISIBILITY void
LLVMInitializeCellSPUTargetMC() {
  RegisterMCAsmInfo<SPULinuxMCAsmInfo> AsmInfo(TheCellSPUTarget);
  TargetRegistry::RegisterMCInstrInfo(TheCellSPUTarget, createSPUMCInstrInfo);
  TargetRegistry::RegisterMCRegInfo(TheCellSPUTarget,
                                    createSPUMCRegisterInfo);
  TargetRegistry::RegisterMCSubtargetInfo(TheCellSPUTarget,
                                          createSPUMCSubtargetInfo);
  TargetRegistry::RegisterMCInstPrinter(TheCellSPUTarget,
                                        createSPUMCInstPrinter);
  TargetRegistry::RegisterMCCodeEmitter(TheCellSPUTarget,
                                        createSPUMCCodeEmitter);
  TargetRegistry::RegisterMCAsmBackend(TheCellSPUTarget,
                                       createSPUAsmBackend);
}
