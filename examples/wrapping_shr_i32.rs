#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn wrapping_shr_i32(value: i32, shift: u32) -> i32 {
    value.wrapping_shr(shift)
}
