//===-- SPUMCAsmInfo.h - Cell SPU asm properties ---------------*- C++ -*--===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file contains the declaration of the SPUMCAsmInfo class.
//
//===----------------------------------------------------------------------===//

#ifndef SPUTARGETASMINFO_H
#define SPUTARGETASMINFO_H

#include "llvm/MC/MCAsmInfoELF.h"

namespace llvm {
  class MCTargetOptions;
  class Triple;

  class SPULinuxMCAsmInfo : public MCAsmInfoELF {
    virtual void anchor();
  public:
    explicit SPULinuxMCAsmInfo(const Triple &TT,
                               const MCTargetOptions &Options);
  };
} // namespace llvm

#endif /* SPUTARGETASMINFO_H */
