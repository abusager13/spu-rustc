#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn add_wide_constant(value: u32) -> u32 {
    value + 0x1234_5678
}
