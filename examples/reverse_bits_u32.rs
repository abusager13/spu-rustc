#![no_std]

#[no_mangle]
pub extern "C" fn reverse_bits_u32(value: u32) -> u32 {
    value.reverse_bits()
}
