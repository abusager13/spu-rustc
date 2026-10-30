//===-- SPUMachineFunctionInfo.h - Private data used for CellSPU --*- C++ -*-=//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file declares the IBM Cell SPU specific subclass of MachineFunctionInfo.
//
//===----------------------------------------------------------------------===//

#ifndef SPU_MACHINE_FUNCTION_INFO_H
#define SPU_MACHINE_FUNCTION_INFO_H

#include "llvm/CodeGen/MachineFunction.h"

namespace llvm {

/// SPUFunctionInfo - Cell SPU target-specific information for each
/// MachineFunction
class SPUFunctionInfo : public MachineFunctionInfo {
  virtual void anchor();

  /// UsesLR - Indicates whether LR is used in the current function.
  ///
  bool UsesLR;

  // VarArgsFrameIndex - FrameIndex for start of varargs area.
  int VarArgsFrameIndex;

  /// Stack-passed formal arguments need an extra linkage-area bias when the
  /// function prologue moves $sp below the caller's stack pointer. These frame
  /// indices are created consecutively during formal argument lowering.
  int FirstIncomingArgFrameIndex;
  int LastIncomingArgFrameIndex;

public:
  SPUFunctionInfo(const Function &F, const TargetSubtargetInfo *STI)
  : UsesLR(false),
    VarArgsFrameIndex(0),
    FirstIncomingArgFrameIndex(0),
    LastIncomingArgFrameIndex(0)
  {}

  void setUsesLR(bool U) { UsesLR = U; }
  bool usesLR()          { return UsesLR; }

  int getVarArgsFrameIndex() const { return VarArgsFrameIndex; }
  void setVarArgsFrameIndex(int Index) { VarArgsFrameIndex = Index; }

  void addIncomingArgFrameIndex(int Index) {
    if (FirstIncomingArgFrameIndex == 0)
      FirstIncomingArgFrameIndex = Index;
    LastIncomingArgFrameIndex = Index;
  }
  bool isIncomingArgFrameIndex(int Index) const {
    return FirstIncomingArgFrameIndex != 0 &&
           Index <= FirstIncomingArgFrameIndex &&
           Index >= LastIncomingArgFrameIndex;
  }
};

} // end of namespace llvm


#endif
