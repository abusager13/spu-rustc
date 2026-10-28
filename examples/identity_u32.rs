#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn identity_u32(value: u32) -> u32 {
    value
}
