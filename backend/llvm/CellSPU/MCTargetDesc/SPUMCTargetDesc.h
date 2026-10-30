//===-- SPUMCTargetDesc.h - CellSPU Target Descriptions ---------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file provides CellSPU specific target descriptions.
//
//===----------------------------------------------------------------------===//

#ifndef SPUMCTARGETDESC_H
#define SPUMCTARGETDESC_H

#include <memory>

namespace llvm {
class Target;
class MCAsmBackend;
class MCCodeEmitter;
class MCContext;
class MCInstrInfo;
class MCObjectTargetWriter;
class MCRegisterInfo;
class MCSubtargetInfo;
class MCTargetOptions;

extern Target TheCellSPUTarget;

MCCodeEmitter *createSPUMCCodeEmitter(const MCInstrInfo &II, MCContext &Ctx);
MCAsmBackend *createSPUAsmBackend(const Target &T,
                                  const MCSubtargetInfo &STI,
                                  const MCRegisterInfo &MRI,
                                  const MCTargetOptions &Options);
std::unique_ptr<MCObjectTargetWriter> createSPUELFObjectWriter();

} // End llvm namespace

// Define symbolic names for Cell registers.  This defines a mapping from
// register name to register number.
//
#define GET_REGINFO_ENUM
#include "SPUGenRegisterInfo.inc"

// Defines symbolic names for the SPU instructions.
//
#define GET_INSTRINFO_ENUM
#include "SPUGenInstrInfo.inc"

#define GET_SUBTARGETINFO_ENUM
#include "SPUGenSubtargetInfo.inc"

#endif
