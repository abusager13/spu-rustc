#![no_std]

#[no_mangle]
pub extern "C" fn saturating_add_i32(lhs: i32, rhs: i32) -> i32 {
    lhs.saturating_add(rhs)
}
