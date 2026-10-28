#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn wide_constant_u32() -> u32 {
    0x1234_5678
}
