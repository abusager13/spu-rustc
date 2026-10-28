#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn and_low_byte(a: u32) -> u32 {
    a & 255
}
