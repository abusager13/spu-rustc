#![no_std]

#[no_mangle]
pub extern "C" fn swap_bytes_u32(value: u32) -> u32 {
    value.swap_bytes()
}
