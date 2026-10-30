//===-- SPUInstrInfo.h - Cell SPU Instruction Information -------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file contains the CellSPU implementation of the TargetInstrInfo class.
//
//===----------------------------------------------------------------------===//

#ifndef SPU_INSTRUCTIONINFO_H
#define SPU_INSTRUCTIONINFO_H

#include "SPU.h"
#include "SPURegisterInfo.h"
#include "llvm/CodeGen/TargetInstrInfo.h"

#define GET_INSTRINFO_HEADER
#include "SPUGenInstrInfo.inc"

namespace llvm {
  class SPUSubtarget;

  //! Cell SPU instruction information class
  class SPUInstrInfo : public SPUGenInstrInfo {
    const SPUSubtarget &STI;
  public:
    explicit SPUInstrInfo(const SPUSubtarget &STI);

    ScheduleHazardRecognizer *
    CreateTargetHazardRecognizer(const TargetSubtargetInfo *STI,
                                 const ScheduleDAG *DAG) const;

    unsigned isLoadFromStackSlot(const MachineInstr *MI,
                                 int &FrameIndex) const;
    unsigned isStoreToStackSlot(const MachineInstr *MI,
                                int &FrameIndex) const;

    void copyPhysReg(MachineBasicBlock &MBB,
                     MachineBasicBlock::iterator I, const DebugLoc &DL,
                     Register DestReg, Register SrcReg, bool KillSrc,
                     bool RenamableDest = false,
                     bool RenamableSrc = false) const override;

    //! Store a register to a stack slot, based on its register class.
    void storeRegToStackSlot(MachineBasicBlock &MBB,
                             MachineBasicBlock::iterator MBBI,
                             Register SrcReg, bool isKill, int FrameIndex,
                             const TargetRegisterClass *RC, Register VReg,
                             MachineInstr::MIFlag Flags) const override;

    //! Load a register from a stack slot, based on its register class.
    void loadRegFromStackSlot(MachineBasicBlock &MBB,
                              MachineBasicBlock::iterator MBBI,
                              Register DestReg, int FrameIndex,
                              const TargetRegisterClass *RC, Register VReg,
                              unsigned SubReg,
                              MachineInstr::MIFlag Flags) const override;

    //! Reverses a branch's condition, returning false on success.
    bool reverseBranchCondition(
        SmallVectorImpl<MachineOperand> &Cond) const override;

    bool analyzeBranch(MachineBasicBlock &MBB, MachineBasicBlock *&TBB,
                       MachineBasicBlock *&FBB,
                       SmallVectorImpl<MachineOperand> &Cond,
                       bool AllowModify = false) const override;

    unsigned removeBranch(MachineBasicBlock &MBB,
                          int *BytesRemoved = nullptr) const override;

    unsigned insertBranch(MachineBasicBlock &MBB, MachineBasicBlock *TBB,
                          MachineBasicBlock *FBB,
                          ArrayRef<MachineOperand> Cond, const DebugLoc &DL,
                          int *BytesAdded = nullptr) const override;
   };
}

#endif
