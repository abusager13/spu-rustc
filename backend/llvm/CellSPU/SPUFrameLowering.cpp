//===-- SPUTargetMachine.cpp - Define TargetMachine for Cell SPU ----------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// Top-level implementation for the Cell SPU target.
//
//===----------------------------------------------------------------------===//

#include "SPUFrameLowering.h"
#include "SPU.h"
#include "SPUInstrBuilder.h"
#include "SPUInstrInfo.h"
#include "SPUSubtarget.h"
#include "llvm/IR/Function.h"
#include "llvm/CodeGen/MachineFrameInfo.h"
#include "llvm/CodeGen/MachineFunction.h"
#include "llvm/CodeGen/MachineInstrBuilder.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/CodeGen/MachineRegisterInfo.h"
#include "llvm/CodeGen/RegisterScavenging.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/Target/TargetOptions.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/Alignment.h"
using namespace llvm;

//===----------------------------------------------------------------------===//
// SPUFrameLowering:
//===----------------------------------------------------------------------===//

SPUFrameLowering::SPUFrameLowering(const SPUSubtarget &sti)
  : TargetFrameLowering(TargetFrameLowering::StackGrowsDown, Align(16), 0),
    Subtarget(sti) {
  LR[0].first = SPU::R0;
  LR[0].second = 16;
}

MachineBasicBlock::iterator
SPUFrameLowering::eliminateCallFramePseudoInstr(
    MachineFunction &, MachineBasicBlock &MBB,
    MachineBasicBlock::iterator I) const {
  // The frame layout reserves outgoing argument space in the function frame.
  return MBB.erase(I);
}


//--------------------------------------------------------------------------
// hasFP - Return true if the specified function actually has a dedicated frame
// pointer register.  This is true if the function needs a frame pointer and has
// a non-zero stack size.
bool SPUFrameLowering::hasFPImpl(const MachineFunction &MF) const {
  const MachineFrameInfo *MFI = &MF.getFrameInfo();

  return MFI->getStackSize() &&
    (MF.getTarget().Options.DisableFramePointerElim(MF) ||
     MFI->hasVarSizedObjects());
}


/// determineFrameLayout - Determine the size of the frame and maximum call
/// frame size.
void SPUFrameLowering::determineFrameLayout(MachineFunction &MF) const {
  MachineFrameInfo *MFI = &MF.getFrameInfo();

  // Get the number of bytes to allocate from the FrameInfo
  unsigned FrameSize = MFI->getStackSize();

  // Get the alignments provided by the target, and the maximum alignment
  // (if any) of the fixed frame objects.
  unsigned TargetAlign = getStackAlignment();
  unsigned FrameAlign = static_cast<unsigned>(
      std::max<uint64_t>(TargetAlign, MFI->getMaxAlign().value()));
  assert(isPowerOf2_32(FrameAlign) && "Alignment is not power of 2");
  unsigned AlignMask = FrameAlign - 1;

  // Get the maximum call frame size of all the calls.
  unsigned maxCallFrameSize = MFI->getMaxCallFrameSize();

  // If we have dynamic alloca then maxCallFrameSize needs to be aligned so
  // that allocations will be aligned.
  if (MFI->hasVarSizedObjects())
    maxCallFrameSize = (maxCallFrameSize + AlignMask) & ~AlignMask;

  // Update maximum call frame size.
  MFI->setMaxCallFrameSize(maxCallFrameSize);

  // Include call frame size in total.
  FrameSize += maxCallFrameSize;

  // Make sure the frame is aligned.
  FrameSize = (FrameSize + AlignMask) & ~AlignMask;

  // Update frame info.
  MFI->setStackSize(FrameSize);
}

void SPUFrameLowering::emitPrologue(MachineFunction &MF,
                                     MachineBasicBlock &MBB) const {
  MachineBasicBlock::iterator MBBI = MBB.begin();
  MachineFrameInfo *MFI = &MF.getFrameInfo();
  const SPUInstrInfo &TII = *MF.getSubtarget<SPUSubtarget>().getInstrInfo();
  DebugLoc dl = MBBI != MBB.end() ? MBBI->getDebugLoc() : DebugLoc();

  // Move MBBI back to the beginning of the function.
  MBBI = MBB.begin();

  // Work out frame sizes.
  determineFrameLayout(MF);
  int FrameSize = MFI->getStackSize();

  assert((FrameSize & 0xf) == 0
         && "SPURegisterInfo::emitPrologue: FrameSize not aligned");

  // the "empty" frame size is 16 - just the register scavenger spill slot
  if (FrameSize > 16 || MFI->adjustsStack()) {
    FrameSize = -(FrameSize + SPUFrameLowering::minStackSize());
    // Adjust stack pointer, spilling $lr -> 16($sp) and $sp -> -FrameSize($sp)
    // for the ABI
    BuildMI(MBB, MBBI, dl, TII.get(SPU::STQDr32)).addReg(SPU::R0).addImm(16)
      .addReg(SPU::R1);
    if (isInt<10>(FrameSize)) {
      // Spill $sp to adjusted $sp
      BuildMI(MBB, MBBI, dl, TII.get(SPU::STQDr32)).addReg(SPU::R1)
        .addImm(FrameSize).addReg(SPU::R1);
      // Adjust $sp by required amout
      BuildMI(MBB, MBBI, dl, TII.get(SPU::AIr32), SPU::R1).addReg(SPU::R1)
        .addImm(FrameSize);
    } else if (isInt<16>(FrameSize)) {
      // Frame size can be loaded into ILr32n, so temporarily spill $r2 and use
      // $r2 to adjust $sp:
      BuildMI(MBB, MBBI, dl, TII.get(SPU::STQDr128)).addReg(SPU::R2)
        .addImm(-16)
        .addReg(SPU::R1);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::ILr32), SPU::R2)
        .addImm(FrameSize);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::STQXr32)).addReg(SPU::R1)
        .addReg(SPU::R2).addReg(SPU::R1);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::Ar32), SPU::R1)
        .addReg(SPU::R1)
        .addReg(SPU::R2);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::SFIr32), SPU::R2)
        .addReg(SPU::R2)
        .addImm(16);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::LQXr128), SPU::R2)
        .addReg(SPU::R2)
        .addReg(SPU::R1);
    } else {
      report_fatal_error("Unhandled frame size: " + Twine(FrameSize));
    }

  }
}

void SPUFrameLowering::emitEpilogue(MachineFunction &MF,
                                MachineBasicBlock &MBB) const {
  MachineBasicBlock::iterator MBBI = MBB.getLastNonDebugInstr();
  const SPUInstrInfo &TII =
  *MF.getSubtarget<SPUSubtarget>().getInstrInfo();
  const MachineFrameInfo *MFI = &MF.getFrameInfo();
  int FrameSize = MFI->getStackSize();
  int LinkSlotOffset = SPUFrameLowering::stackSlotSize();
  DebugLoc dl = MBBI->getDebugLoc();

  assert(MBBI->getOpcode() == SPU::RET &&
         "Can only insert epilog into returning blocks");
  assert((FrameSize & 0xf) == 0 && "FrameSize not aligned");

  // the "empty" frame size is 16 - just the register scavenger spill slot
  if (FrameSize > 16 || MFI->adjustsStack()) {
    FrameSize = FrameSize + SPUFrameLowering::minStackSize();
    if (isInt<10>(FrameSize + LinkSlotOffset)) {
      // Reload $lr, adjust $sp by required amount
      // Note: We do this to slightly improve dual issue -- not by much, but it
      // is an opportunity for dual issue.
      BuildMI(MBB, MBBI, dl, TII.get(SPU::LQDr128), SPU::R0)
        .addImm(FrameSize + LinkSlotOffset)
        .addReg(SPU::R1);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::AIr32), SPU::R1)
        .addReg(SPU::R1)
        .addImm(FrameSize);
    } else if (FrameSize <= (1 << 16) - 1 && FrameSize >= -(1 << 16)) {
      // Frame size can be loaded into ILr32n, so temporarily spill $r2 and use
      // $r2 to adjust $sp:
      BuildMI(MBB, MBBI, dl, TII.get(SPU::STQDr128)).addReg(SPU::R2)
        .addImm(16)
        .addReg(SPU::R1);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::ILr32), SPU::R2)
        .addImm(FrameSize);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::Ar32), SPU::R1)
        .addReg(SPU::R1)
        .addReg(SPU::R2);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::LQDr128), SPU::R0)
        .addImm(16)
        .addReg(SPU::R1);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::SFIr32), SPU::R2).
        addReg(SPU::R2)
        .addImm(16);
      BuildMI(MBB, MBBI, dl, TII.get(SPU::LQXr128), SPU::R2)
        .addReg(SPU::R2)
        .addReg(SPU::R1);
    } else {
      report_fatal_error("Unhandled frame size: " + Twine(FrameSize));
    }
  }
}

void SPUFrameLowering::processFunctionBeforeCalleeSavedScan(MachineFunction &MF,
                                                        RegScavenger *RS) const{
  if (RS)
    RS->addScavengingFrameIndex(
        MF.getFrameInfo().CreateSpillStackObject(16, Align(16)));
}
