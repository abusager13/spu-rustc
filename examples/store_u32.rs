#![no_std]

#[no_mangle]
pub unsafe extern "C" fn store_u32(pointer: *mut u32, value: u32) -> u32 {
    unsafe { pointer.write(value) };
    value
}
