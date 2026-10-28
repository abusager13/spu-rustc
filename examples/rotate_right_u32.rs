#![no_std]

#[no_mangle]
pub extern "C" fn rotate_right_u32(value: u32, count: u32) -> u32 {
    value.rotate_right(count)
}
