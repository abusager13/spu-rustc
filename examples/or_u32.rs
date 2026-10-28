#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn or_u32(a: u32, b: u32) -> u32 {
    a | b
}
