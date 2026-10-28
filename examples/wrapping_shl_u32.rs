#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn wrapping_shl_u32(value: u32, shift: u32) -> u32 {
    value.wrapping_shl(shift)
}
