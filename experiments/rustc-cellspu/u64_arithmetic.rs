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

impl Copy for u32 {}
impl Copy for u64 {}

#[lang = "add"]
pub trait Add<Rhs = Self> {
    type Output;
    fn add(self, rhs: Rhs) -> Self::Output;
}

impl Add for u64 {
    type Output = u64;

    fn add(self, rhs: u64) -> u64 {
        self + rhs
    }
}

#[lang = "sub"]
pub trait Sub<Rhs = Self> {
    type Output;
    fn sub(self, rhs: Rhs) -> Self::Output;
}

impl Sub for u64 {
    type Output = u64;

    fn sub(self, rhs: u64) -> u64 {
        self - rhs
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
#[unsafe(no_mangle)]
pub fn add_u64(lhs: u64, rhs: u64) -> u64 {
    lhs + rhs
}

#[unsafe(no_mangle)]
pub fn carry_word(lhs: u32, rhs: u32) -> u32 {
    (add_u64(lhs as u64, rhs as u64) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn high_word_sum() -> u32 {
    (add_u64(0x1234_5678_9abc_def0, 0x1111_2222_3333_4444) >> 32) as u32
}

#[inline(never)]
#[unsafe(no_mangle)]
pub fn sub_u64(lhs: u64, rhs: u64) -> u64 {
    lhs - rhs
}

#[unsafe(no_mangle)]
pub fn borrow_word(lhs: u32, rhs: u32) -> u32 {
    (sub_u64(lhs as u64, rhs as u64) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn high_word_difference() -> u32 {
    (sub_u64(0x1234_5678_9abc_def0, 0x1111_2222_3333_4444) >> 32) as u32
}
