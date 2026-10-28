#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn not_u32(value: u32) -> u32 {
    !value
}
