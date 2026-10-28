#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn scalar_entry() -> u32 {
    40 + 2
}
