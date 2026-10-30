#![feature(no_core, lang_items)]
#![allow(internal_features)]
#![no_core]

#[lang = "pointee_sized"]
pub trait PointeeSized {}

#[lang = "meta_sized"]
pub trait MetaSized: PointeeSized {}

#[lang = "sized"]
pub trait Sized: MetaSized {}

#[lang = "copy"]
pub trait Copy: Sized {}

impl Copy for u64 {}

#[lang = "mul"]
pub trait Mul<Rhs = Self> {
    type Output;
    fn mul(self, rhs: Rhs) -> Self::Output;
}

impl Mul for u64 {
    type Output = u64;

    fn mul(self, rhs: u64) -> u64 {
        self * rhs
    }
}

#[lang = "shr"]
pub trait Shr<Rhs = Self> {
    type Output;
    fn shr(self, rhs: Rhs) -> Self::Output;
}

impl Shr<u32> for u64 {
    type Output = u64;

    fn shr(self, rhs: u32) -> u64 {
        self >> rhs
    }
}

#[inline(never)]
fn wrapping_mul(lhs: u64, rhs: u64) -> u64 {
    lhs * rhs
}

#[unsafe(no_mangle)]
pub fn product_0_low() -> u32 {
    wrapping_mul(0x0000_0001_0000_0002, 0x0000_0003_0000_0004) as u32
}

#[unsafe(no_mangle)]
pub fn product_0_high() -> u32 {
    (wrapping_mul(0x0000_0001_0000_0002, 0x0000_0003_0000_0004) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn product_1_low() -> u32 {
    wrapping_mul(0xffff_ffff_ffff_ffff, 2) as u32
}

#[unsafe(no_mangle)]
pub fn product_1_high() -> u32 {
    (wrapping_mul(0xffff_ffff_ffff_ffff, 2) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn product_2_low() -> u32 {
    wrapping_mul(0x0123_4567_89ab_cdef, 0xfedc_ba98_7654_3210) as u32
}

#[unsafe(no_mangle)]
pub fn product_2_high() -> u32 {
    (wrapping_mul(0x0123_4567_89ab_cdef, 0xfedc_ba98_7654_3210) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn product_3_low() -> u32 {
    wrapping_mul(0x8000_0000_8000_0000, 0x0000_0002_0000_0003) as u32
}

#[unsafe(no_mangle)]
pub fn product_3_high() -> u32 {
    (wrapping_mul(0x8000_0000_8000_0000, 0x0000_0002_0000_0003) >> 32) as u32
}
