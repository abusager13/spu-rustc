#![no_std]

#[no_mangle]
pub unsafe extern "C" fn load_u32(pointer: *const u32) -> u32 {
    pointer.read()
}
