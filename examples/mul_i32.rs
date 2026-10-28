#![no_std]

#[no_mangle]
pub extern "C" fn mul_i32(lhs: i32, rhs: i32) -> i32 {
    lhs.wrapping_mul(rhs)
}
