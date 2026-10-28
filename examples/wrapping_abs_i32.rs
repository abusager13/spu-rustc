#![no_std]

#[no_mangle]
pub extern "C" fn wrapping_abs_i32(value: i32) -> i32 {
    value.wrapping_abs()
}
