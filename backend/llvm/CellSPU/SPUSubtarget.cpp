//===-- SPUSubtarget.cpp - STI Cell SPU Subtarget Information -------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements the CellSPU-specific subclass of TargetSubtargetInfo.
//
//===----------------------------------------------------------------------===//

#include "SPUSubtarget.h"
#include "SPU.h"
#include "SPURegisterInfo.h"
#include "llvm/IR/RuntimeLibcalls.h"
#include "llvm/MC/TargetRegistry.h"

#define GET_SUBTARGETINFO_TARGET_DESC
#define GET_SUBTARGETINFO_CTOR
#include "SPUGenSubtargetInfo.inc"

using namespace llvm;

SPUSubtarget::SPUSubtarget(const Triple &TT, const std::string &CPU,
                           const std::string &FS, SPUTargetMachine &TM) :
  SPUGenSubtargetInfo(TT, CPU, CPU, FS),
  StackAlignment(16),
  ProcDirective(SPU::DEFAULT_PROC),
  UseLargeMem(false),
  UseShortCalls(false),
  RegisterInfo(*this),
  InstrInfo(*this),
  FrameLowering(*this),
  TLInfo(TM, *this)
{
  // Should be the target SPU processor type. For now, since there's only
  // one, simply default to the current "v0" default:
  std::string default_cpu = CPU.empty() ? "v0" : CPU;

  // Parse features string.
  ParseSubtargetFeatures(default_cpu, default_cpu, FS);

  // Initialize scheduling itinerary for the specified CPU.
  InstrItins = getInstrItineraryForCPU(default_cpu);
}

void SPUSubtarget::initLibcallLoweringInfo(LibcallLoweringInfo &Info) const {
  static constexpr struct {
    RTLIB::Libcall Op;
    RTLIB::LibcallImpl Impl;
  } DivisionLibcalls[] = {
      {RTLIB::SDIV_I32, RTLIB::impl___divsi3},
      {RTLIB::UDIV_I32, RTLIB::impl___udivsi3},
      {RTLIB::SREM_I32, RTLIB::impl___modsi3},
      {RTLIB::UREM_I32, RTLIB::impl___umodsi3},
      {RTLIB::SDIV_I64, RTLIB::impl___divdi3},
      {RTLIB::UDIV_I64, RTLIB::impl___udivdi3},
      {RTLIB::SREM_I64, RTLIB::impl___moddi3},
      {RTLIB::UREM_I64, RTLIB::impl___umoddi3},
  };

  for (const auto &LC : DivisionLibcalls)
    Info.setLibcallImpl(LC.Op, LC.Impl);
}

/// SetJITMode - This is called to inform the subtarget info that we are
/// producing code for the JIT.
void SPUSubtarget::SetJITMode() {
}
