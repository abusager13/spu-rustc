#![feature(no_core, lang_items)]
#![allow(internal_features)]
#![no_core]

// Minimal lang items for a no_core compiler probe. This is not a replacement
// for core and does not claim ordinary no_std crate support.
#[lang = "pointee_sized"]
pub trait PointeeSized {}

#[lang = "meta_sized"]
pub trait MetaSized: PointeeSized {}

#[lang = "sized"]
pub trait Sized: MetaSized {}

#[lang = "copy"]
pub trait Copy: Sized {}

impl Copy for u32 {}

#[lang = "add"]
pub trait Add<Rhs = Self> {
    type Output;
    fn add(self, rhs: Rhs) -> Self::Output;
}

impl Add for u32 {
    type Output = u32;

    fn add(self, rhs: u32) -> u32 {
        self + rhs
    }
}

#[unsafe(no_mangle)]
pub fn add_u32(lhs: u32, rhs: u32) -> u32 {
    lhs + rhs
}
