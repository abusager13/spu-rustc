#![no_std]

#[no_mangle]
pub extern "C" fn rotate_right_const_u32(value: u32) -> u32 {
    value.rotate_right(5)
}
