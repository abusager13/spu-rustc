#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn wrapping_shr_const_u32(value: u32) -> u32 {
    value.wrapping_shr(5)
}
