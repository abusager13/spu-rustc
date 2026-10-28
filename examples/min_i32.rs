#![no_std]

#[no_mangle]
pub extern "C" fn min_i32(lhs: i32, rhs: i32) -> i32 {
    lhs.min(rhs)
}
