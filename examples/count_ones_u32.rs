#![no_std]

#[no_mangle]
pub extern "C" fn count_ones_u32(value: u32) -> u32 {
    value.count_ones()
}
