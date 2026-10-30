add_llvm_component_library(LLVMCellSPUInfo
  CellSPUTargetInfo.cpp

  LINK_COMPONENTS
  MC
  Support
  TargetParser

  ADD_TO_COMPONENT
  CellSPU
  )

add_dependencies(LLVMCellSPUInfo CellSPUCommonTableGen)
