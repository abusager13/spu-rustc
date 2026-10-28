#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn or_low_bit(a: u32) -> u32 {
    a | 1
}
