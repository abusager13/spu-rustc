#![no_std]

#[no_mangle]
pub extern "C" fn select_i32(lhs: i32, rhs: i32) -> i32 {
    if lhs > 0 { lhs } else { rhs }
}
