#![no_std]

#[no_mangle]
pub extern "C" fn select_computed_i32(lhs: i32, rhs: i32) -> i32 {
    if lhs > 0 {
        rhs.wrapping_add(7)
    } else {
        lhs ^ rhs
    }
}
