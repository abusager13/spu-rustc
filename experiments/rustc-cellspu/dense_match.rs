#![feature(no_core, lang_items)]
#![allow(internal_features)]
#![no_core]

// Exercise the dense match shape used by a Rust enum or integer dispatch:
// LLVM lowers this ten-arm match to a constant lookup table plus a fallback.
// The tiny lang-item set keeps this a direct backend probe, not a `core` test.
#[lang = "pointee_sized"]
pub trait PointeeSized {}

#[lang = "meta_sized"]
pub trait MetaSized: PointeeSized {}

#[lang = "sized"]
pub trait Sized: MetaSized {}

#[lang = "copy"]
pub trait Copy: Sized {}

impl Copy for u32 {}

#[unsafe(no_mangle)]
pub fn classify(value: u32) -> u32 {
    match value {
        0 => 0x1357_9bdf,
        1 => 0x2468_ace0,
        2 => 0x0f0f_55aa,
        3 => 0xfedc_ba98,
        4 => 0x89ab_cdef,
        5 => 0x8765_4321,
        6 => 0xa55a_a55a,
        7 => 0x5aa5_5aa5,
        8 => 0x1122_3344,
        9 => 0xc001_d00d,
        _ => 0x0000_0b0b,
    }
}
