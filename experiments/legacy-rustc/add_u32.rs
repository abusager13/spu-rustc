#![no_core]
#![feature(intrinsics, no_core, lang_items)]

#[lang = "sized"]
pub trait Sized {}

#[lang = "copy"]
pub trait Copy {}
impl Copy for u32 {}

extern "rust-intrinsic" {
    fn wrapping_add<T>(lhs: T, rhs: T) -> T;
}

#[no_mangle]
pub fn add_u32(lhs: u32, rhs: u32) -> u32 {
    wrapping_add(lhs, rhs)
}
