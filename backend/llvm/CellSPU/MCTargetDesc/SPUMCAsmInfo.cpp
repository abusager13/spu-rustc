//===-- SPUMCAsmInfo.cpp - Cell SPU asm properties ------------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file contains the declarations of the SPUMCAsmInfo properties.
//
//===----------------------------------------------------------------------===//

#include "SPUMCAsmInfo.h"
#include "llvm/TargetParser/Triple.h"
using namespace llvm;

void SPULinuxMCAsmInfo::anchor() { }

SPULinuxMCAsmInfo::SPULinuxMCAsmInfo(const Triple &TT,
                                     const MCTargetOptions &Options)
    : MCAsmInfoELF(Options) {
  IsLittleEndian = false;
  MinInstAlignment = 4;

  ZeroDirective = "\t.space\t";
  Data64bitsDirective = "\t.quad\t";
  AlignmentIsInBytes = false;

  CommentString = "#";
  InternalSymbolPrefix = ".L";

  // Has leb128
  HasLEB128Directives = true;

  SupportsDebugInformation = true;

  // Exception handling is not supported on CellSPU (think about it: you only
  // have 256K for code+data. Would you support exception handling?)
  ExceptionsType = ExceptionHandling::None;

  // SPU assembly requires ".section" before ".bss"
  UsesELFSectionDirectiveForBSS = true;
}
