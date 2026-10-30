add_llvm_component_library(LLVMCellSPUDesc
  SPUMCTargetDesc.cpp
  SPUMCAsmInfo.cpp

  LINK_COMPONENTS
  CellSPUInfo
  MC
  Support
  TargetParser

  ADD_TO_COMPONENT
  CellSPU
  )

add_dependencies(LLVMCellSPUDesc CellSPUCommonTableGen)

# The target's private generated headers are shared with the parent target.
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/.. ${CMAKE_CURRENT_BINARY_DIR}/..)
