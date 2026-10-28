#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn xor_low_bit(a: u32) -> u32 {
    a ^ 1
}
