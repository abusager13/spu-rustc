#![no_std]

#[no_mangle]
pub extern "C" fn leading_ones_u32(value: u32) -> u32 {
    value.leading_ones()
}
