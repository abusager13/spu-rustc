#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn add_large_constant(value: u32) -> u32 {
    value + 4096
}
