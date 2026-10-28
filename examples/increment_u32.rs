#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn increment_u32(a: u32) -> u32 {
    a + 1
}
