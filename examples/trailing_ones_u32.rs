#![no_std]

#[no_mangle]
pub extern "C" fn trailing_ones_u32(value: u32) -> u32 {
    value.trailing_ones()
}
