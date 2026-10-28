#![no_std]

#[no_mangle]
pub extern "C" fn rotate_left_u32(value: u32, count: u32) -> u32 {
    value.rotate_left(count)
}
