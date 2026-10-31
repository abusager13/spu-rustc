#![feature(no_core, lang_items)]
#![allow(internal_features)]
#![no_core]

// This optimized sparse match makes LLVM split the cases with a signed i64
// comparison. In particular, zero must stay below 0x00000000ffffffff.
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

#[inline(never)]
#[unsafe(no_mangle)]
pub fn classify_u64(value: u64) -> u32 {
    match value {
        0 => 0x1111_0000,
        0x0000_0001_0000_0000 => 0x2222_0000,
        0x0000_0010_0000_0000 => 0x3333_0000,
        0x0000_00ff_ffff_ffff => 0x4444_0000,
        0xffff_ffff_ffff_ffff => 0x5555_0000,
        _ => 0xaaaa_0000,
    }
}

#[unsafe(no_mangle)]
pub fn match64_zero() -> u32 { classify_u64(0) }
#[unsafe(no_mangle)]
pub fn match64_one_high() -> u32 { classify_u64(0x0000_0001_0000_0000) }
#[unsafe(no_mangle)]
pub fn match64_sixteen_high() -> u32 { classify_u64(0x0000_0010_0000_0000) }
#[unsafe(no_mangle)]
pub fn match64_ff_high() -> u32 { classify_u64(0x0000_00ff_ffff_ffff) }
#[unsafe(no_mangle)]
pub fn match64_max() -> u32 { classify_u64(0xffff_ffff_ffff_ffff) }
#[unsafe(no_mangle)]
pub fn match64_mixed() -> u32 { classify_u64(0x1234_5678_9abc_def0) }
#[unsafe(no_mangle)]
pub fn match64_low_signed_max() -> u32 { classify_u64(0x7fff_ffff) }
#[unsafe(no_mangle)]
pub fn match64_low_sign_bit() -> u32 { classify_u64(0x8000_0000) }
#[unsafe(no_mangle)]
pub fn match64_low_max() -> u32 { classify_u64(0xffff_ffff) }
#[unsafe(no_mangle)]
pub fn match64_one_high_plus_one() -> u32 { classify_u64(0x0000_0001_0000_0001) }
#[unsafe(no_mangle)]
pub fn match64_sign_bit() -> u32 { classify_u64(0x8000_0000_0000_0000) }
