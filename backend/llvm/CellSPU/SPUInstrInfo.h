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

    virtual void copyPhysReg(MachineBasicBlock &MBB,
                             MachineBasicBlock::iterator I, DebugLoc DL,
                             unsigned DestReg, unsigned SrcReg,
                             bool KillSrc) const;

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
    virtual
    bool ReverseBranchCondition(SmallVectorImpl<MachineOperand> &Cond) const;

    virtual bool AnalyzeBranch(MachineBasicBlock &MBB, MachineBasicBlock *&TBB,
                               MachineBasicBlock *&FBB,
                               SmallVectorImpl<MachineOperand> &Cond,
                               bool AllowModify) const;

    virtual unsigned RemoveBranch(MachineBasicBlock &MBB) const;

    virtual unsigned InsertBranch(MachineBasicBlock &MBB, MachineBasicBlock *TBB,
                                  MachineBasicBlock *FBB,
                                  const SmallVectorImpl<MachineOperand> &Cond,
                                  DebugLoc DL) const;
   };
}

#endif
