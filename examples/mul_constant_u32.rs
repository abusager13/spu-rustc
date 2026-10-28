#![no_std]

#[no_mangle]
pub extern "C" fn mul_constant_u32(value: u32) -> u32 {
    value.wrapping_mul(0x1234_5678)
}
