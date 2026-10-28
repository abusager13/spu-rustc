#![no_std]

#[no_mangle]
pub extern "C" fn saturating_add_u32(lhs: u32, rhs: u32) -> u32 {
    lhs.saturating_add(rhs)
}
