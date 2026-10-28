#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn cmp_ugt_u32(lhs: u32, rhs: u32) -> bool {
    lhs > rhs
}
