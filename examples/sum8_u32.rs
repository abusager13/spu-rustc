#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn sum8_u32(
    a: u32,
    b: u32,
    c: u32,
    d: u32,
    e: u32,
    f: u32,
    g: u32,
    h: u32,
) -> u32 {
    a + b + c + d + e + f + g + h
}
