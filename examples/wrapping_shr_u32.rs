#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn wrapping_shr_u32(value: u32, shift: u32) -> u32 {
    value.wrapping_shr(shift)
}
