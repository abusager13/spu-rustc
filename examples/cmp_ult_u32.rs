#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn cmp_ult_u32(lhs: u32, rhs: u32) -> bool {
    lhs < rhs
}
