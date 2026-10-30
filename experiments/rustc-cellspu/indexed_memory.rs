#![feature(no_core, lang_items)]
#![allow(internal_features)]
#![no_core]

// Build addresses from a local-store pointer and a word index. This checks the
// indexed LQX/STQX path independently of the dense-match lookup-table load.
#[lang = "pointee_sized"]
pub trait PointeeSized {}

#[lang = "meta_sized"]
pub trait MetaSized: PointeeSized {}

#[lang = "sized"]
pub trait Sized: MetaSized {}

#[lang = "copy"]
pub trait Copy: Sized {}

impl Copy for u32 {}
impl Copy for *const u32 {}
impl Copy for *mut u32 {}

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

#[lang = "shl"]
pub trait Shl<Rhs = Self> {
    type Output;
    fn shl(self, rhs: Rhs) -> Self::Output;
}

impl Shl<u32> for u32 {
    type Output = u32;

    fn shl(self, rhs: u32) -> u32 {
        self << rhs
    }
}

#[unsafe(no_mangle)]
pub unsafe fn load_indexed(pointer: *const u32, index: u32) -> u32 {
    let address = pointer as u32 + (index << 2);
    unsafe { *(address as *const u32) }
}

#[unsafe(no_mangle)]
pub unsafe fn store_indexed(pointer: *mut u32, index: u32, value: u32) {
    let address = pointer as u32 + (index << 2);
    unsafe { *(address as *mut u32) = value }
}
