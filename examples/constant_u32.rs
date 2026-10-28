#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn constant_u32() -> u32 {
    42
}
