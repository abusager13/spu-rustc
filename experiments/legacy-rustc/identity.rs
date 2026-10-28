#![no_core]
#![feature(no_core, lang_items)]

#[lang = "sized"]
pub trait Sized {}

#[lang = "copy"]
pub trait Copy {}

impl Copy for u32 {}

#[no_mangle]
pub fn identity(value: u32) -> u32 {
    value
}
