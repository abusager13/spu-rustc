#![no_std]

#[no_mangle]
pub extern "C" fn mul_u32(lhs: u32, rhs: u32) -> u32 {
    lhs.wrapping_mul(rhs)
}
