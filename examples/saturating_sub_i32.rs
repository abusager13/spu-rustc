#![no_std]

#[no_mangle]
pub extern "C" fn saturating_sub_i32(lhs: i32, rhs: i32) -> i32 {
    lhs.saturating_sub(rhs)
}
