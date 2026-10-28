#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn wrapping_shr_const_i32(value: i32) -> i32 {
    value.wrapping_shr(5)
}
