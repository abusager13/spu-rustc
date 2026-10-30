add_llvm_component_group(CellSPU)

set(LLVM_TARGET_DEFINITIONS SPU.td)
tablegen(LLVM SPUGenAsmWriter.inc -gen-asm-writer)
tablegen(LLVM SPUGenRegisterInfo.inc -gen-register-info)
tablegen(LLVM SPUGenInstrInfo.inc -gen-instr-info)
tablegen(LLVM SPUGenDAGISel.inc -gen-dag-isel)
tablegen(LLVM SPUGenSubtargetInfo.inc -gen-subtarget)
tablegen(LLVM SPUGenCallingConv.inc -gen-callingconv)
add_public_tablegen_target(CellSPUCommonTableGen)

add_llvm_target(CellSPUCodeGen
  SPUAsmPrinter.cpp
  SPUHazardRecognizers.cpp
  SPUInstrInfo.cpp
  SPUISelDAGToDAG.cpp
  SPUISelLowering.cpp
  SPUFrameLowering.cpp
  SPUMachineFunction.cpp
  SPURegisterInfo.cpp
  SPUSubtarget.cpp
  SPUTargetMachine.cpp
  SPUNopFiller.cpp

  DEPENDS
  intrinsics_gen

  LINK_COMPONENTS
  CellSPUDesc
  CellSPUInfo
  Analysis
  AsmPrinter
  CodeGen
  CodeGenTypes
  Core
  MC
  Passes
  SelectionDAG
  Support
  Target
  TargetParser
  TransformUtils

  ADD_TO_COMPONENT
  CellSPU
  )

add_subdirectory(MCTargetDesc)
add_subdirectory(TargetInfo)

include_directories(${CMAKE_CURRENT_BINARY_DIR}/.. ${CMAKE_CURRENT_SOURCE_DIR}/..)
