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
impl Copy for i64 {}

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

impl Shr<u32> for i64 {
    type Output = i64;

    fn shr(self, rhs: u32) -> i64 {
        self >> rhs
    }
}

#[lang = "shl"]
pub trait Shl<Rhs = Self> {
    type Output;
    fn shl(self, rhs: Rhs) -> Self::Output;
}

impl Shl<u32> for u64 {
    type Output = u64;

    fn shl(self, rhs: u32) -> u64 {
        self << rhs
    }
}

#[lang = "bitand"]
pub trait BitAnd<Rhs = Self> {
    type Output;
    fn bitand(self, rhs: Rhs) -> Self::Output;
}

impl BitAnd for u64 {
    type Output = u64;

    fn bitand(self, rhs: u64) -> u64 {
        self & rhs
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

#[inline(never)]
#[unsafe(no_mangle)]
pub fn and_u64(lhs: u64, rhs: u64) -> u64 {
    lhs & rhs
}

#[unsafe(no_mangle)]
pub fn high_word_and() -> u32 {
    (and_u64(0x1234_5678_9abc_def0, 0x0f0f_0f0f_f0f0_f0f0) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn low_word_and() -> u32 {
    and_u64(0x1234_5678_9abc_def0, 0x0f0f_0f0f_f0f0_f0f0) as u32
}

#[inline(never)]
#[unsafe(no_mangle)]
pub fn shl_u64(value: u64, amount: u32) -> u64 {
    value << amount
}

#[unsafe(no_mangle)]
pub fn shift_high(amount: u32) -> u32 {
    (shl_u64(0x8123_4567_89ab_cdef, amount) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn shift_low(amount: u32) -> u32 {
    shl_u64(0x8123_4567_89ab_cdef, amount) as u32
}

#[unsafe(no_mangle)]
pub fn shift_high_value(value: u64, amount: u32) -> u32 {
    (shl_u64(value, amount) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn shift_low_value(value: u64, amount: u32) -> u32 {
    shl_u64(value, amount) as u32
}

#[inline(never)]
#[unsafe(no_mangle)]
pub fn shl_u64_by_13(value: u64) -> u64 {
    value << 13
}

#[unsafe(no_mangle)]
pub fn shift_high_by_13(value: u64, _amount: u32) -> u32 {
    (shl_u64_by_13(value) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn shift_low_by_13(value: u64, _amount: u32) -> u32 {
    shl_u64_by_13(value) as u32
}

#[inline(never)]
#[unsafe(no_mangle)]
pub fn shr_u64(value: u64, amount: u32) -> u64 {
    value >> amount
}

#[unsafe(no_mangle)]
pub fn shift_right_high(value: u64, amount: u32) -> u32 {
    (shr_u64(value, amount) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn shift_right_low(value: u64, amount: u32) -> u32 {
    shr_u64(value, amount) as u32
}

#[inline(never)]
#[unsafe(no_mangle)]
pub fn shr_u64_by_13(value: u64) -> u64 {
    value >> 13
}

#[unsafe(no_mangle)]
pub fn shift_right_high_by_13(value: u64, _amount: u32) -> u32 {
    (shr_u64_by_13(value) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn shift_right_low_by_13(value: u64, _amount: u32) -> u32 {
    shr_u64_by_13(value) as u32
}

#[inline(never)]
#[unsafe(no_mangle)]
pub fn shr_i64(value: i64, amount: u32) -> i64 {
    value >> amount
}

#[unsafe(no_mangle)]
pub fn shift_arithmetic_high(value: i64, amount: u32) -> u32 {
    (shr_i64(value, amount) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn shift_arithmetic_low(value: i64, amount: u32) -> u32 {
    shr_i64(value, amount) as u32
}

#[inline(never)]
#[unsafe(no_mangle)]
pub fn shr_i64_by_13(value: i64) -> i64 {
    value >> 13
}

#[unsafe(no_mangle)]
pub fn shift_arithmetic_high_by_13(value: i64, _amount: u32) -> u32 {
    (shr_i64_by_13(value) >> 32) as u32
}

#[unsafe(no_mangle)]
pub fn shift_arithmetic_low_by_13(value: i64, _amount: u32) -> u32 {
    shr_i64_by_13(value) as u32
}
