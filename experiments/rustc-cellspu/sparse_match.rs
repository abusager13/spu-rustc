#![feature(no_core, lang_items)]
#![allow(internal_features)]
#![no_core]

// Cover a sparse Rust match that LLVM lowers to a comparison tree plus a
// compact jump table for the nearby cases. The fallback must be preserved on
// both sides of the jump-table dispatch.
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
pub fn classify_sparse(value: u32) -> u32 {
    match value {
        0 => 0x1111_0000,
        7 => 0x2222_0000,
        20 => 0x3333_0000,
        100 => 0x4444_0000,
        1000 => 0x5555_0000,
        4096 => 0x6666_0000,
        0xffff_fffe => 0x7777_0000,
        _ => 0xaaaa_0000,
    }
}
