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

impl Copy for u8 {}
impl Copy for i8 {}
impl Copy for u16 {}
impl Copy for i16 {}
impl Copy for u32 {}
impl Copy for i32 {}

#[lang = "add"]
pub trait Add<Rhs = Self> {
    type Output;
    fn add(self, rhs: Rhs) -> Self::Output;
}

#[lang = "sub"]
pub trait Sub<Rhs = Self> {
    type Output;
    fn sub(self, rhs: Rhs) -> Self::Output;
}

#[lang = "mul"]
pub trait Mul<Rhs = Self> {
    type Output;
    fn mul(self, rhs: Rhs) -> Self::Output;
}

#[lang = "bitand"]
pub trait BitAnd<Rhs = Self> {
    type Output;
    fn bitand(self, rhs: Rhs) -> Self::Output;
}

#[lang = "bitor"]
pub trait BitOr<Rhs = Self> {
    type Output;
    fn bitor(self, rhs: Rhs) -> Self::Output;
}

#[lang = "bitxor"]
pub trait BitXor<Rhs = Self> {
    type Output;
    fn bitxor(self, rhs: Rhs) -> Self::Output;
}

#[lang = "shl"]
pub trait Shl<Rhs = Self> {
    type Output;
    fn shl(self, rhs: Rhs) -> Self::Output;
}

#[lang = "shr"]
pub trait Shr<Rhs = Self> {
    type Output;
    fn shr(self, rhs: Rhs) -> Self::Output;
}

impl Add for u16 {
    type Output = u16;
    fn add(self, rhs: u16) -> u16 {
        self + rhs
    }
}

impl Sub for u16 {
    type Output = u16;
    fn sub(self, rhs: u16) -> u16 {
        self - rhs
    }
}

impl Mul for u16 {
    type Output = u16;
    fn mul(self, rhs: u16) -> u16 {
        self * rhs
    }
}

impl BitAnd for u16 {
    type Output = u16;
    fn bitand(self, rhs: u16) -> u16 {
        self & rhs
    }
}

impl BitOr for u16 {
    type Output = u16;
    fn bitor(self, rhs: u16) -> u16 {
        self | rhs
    }
}

impl BitXor for u16 {
    type Output = u16;
    fn bitxor(self, rhs: u16) -> u16 {
        self ^ rhs
    }
}

impl Shl<u32> for u16 {
    type Output = u16;
    fn shl(self, rhs: u32) -> u16 {
        self << rhs
    }
}

impl Shr<u32> for u16 {
    type Output = u16;
    fn shr(self, rhs: u32) -> u16 {
        self >> rhs
    }
}

impl Shr<u32> for i16 {
    type Output = i16;
    fn shr(self, rhs: u32) -> i16 {
        self >> rhs
    }
}

impl Add for u8 {
    type Output = u8;
    fn add(self, rhs: u8) -> u8 {
        self + rhs
    }
}

impl Sub for u8 {
    type Output = u8;
    fn sub(self, rhs: u8) -> u8 {
        self - rhs
    }
}

impl Mul for u8 {
    type Output = u8;
    fn mul(self, rhs: u8) -> u8 {
        self * rhs
    }
}

impl BitAnd for u8 {
    type Output = u8;
    fn bitand(self, rhs: u8) -> u8 {
        self & rhs
    }
}

impl BitOr for u8 {
    type Output = u8;
    fn bitor(self, rhs: u8) -> u8 {
        self | rhs
    }
}

impl BitXor for u8 {
    type Output = u8;
    fn bitxor(self, rhs: u8) -> u8 {
        self ^ rhs
    }
}

impl Mul for u32 {
    type Output = u32;
    fn mul(self, rhs: u32) -> u32 {
        self * rhs
    }
}

#[unsafe(no_mangle)]
pub fn add_u16(a: u16, b: u16) -> u16 {
    a + b
}

#[unsafe(no_mangle)]
pub fn add_u16_imm(a: u16) -> u16 {
    a + 42
}

#[unsafe(no_mangle)]
pub fn sub_u16(a: u16, b: u16) -> u16 {
    a - b
}

#[unsafe(no_mangle)]
pub fn sub_u16_imm(a: u16) -> u16 {
    a - 42
}

#[unsafe(no_mangle)]
pub fn mul_u16(a: u16, b: u16) -> u16 {
    a * b
}

#[unsafe(no_mangle)]
pub fn mul_u16_imm(a: u16) -> u16 {
    a * 10
}

#[unsafe(no_mangle)]
pub fn and_u16(a: u16, b: u16) -> u16 {
    a & b
}

#[unsafe(no_mangle)]
pub fn and_u16_imm(a: u16) -> u16 {
    a & 0x0ff0
}

#[unsafe(no_mangle)]
pub fn or_u16(a: u16, b: u16) -> u16 {
    a | b
}

#[unsafe(no_mangle)]
pub fn or_u16_imm(a: u16) -> u16 {
    a | 0x0ff0
}

#[unsafe(no_mangle)]
pub fn xor_u16(a: u16, b: u16) -> u16 {
    a ^ b
}

#[unsafe(no_mangle)]
pub fn xor_u16_imm(a: u16) -> u16 {
    a ^ 0x0ff0
}

#[unsafe(no_mangle)]
pub fn shl_u16(a: u16, b: u32) -> u16 {
    a << b
}

#[unsafe(no_mangle)]
pub fn shl_u16_imm(a: u16) -> u16 {
    a << 5
}

#[unsafe(no_mangle)]
pub fn shr_u16(a: u16, b: u32) -> u16 {
    a >> b
}

#[unsafe(no_mangle)]
pub fn shr_u16_imm(a: u16) -> u16 {
    a >> 5
}

#[unsafe(no_mangle)]
pub fn ashr_i16(a: i16, b: u32) -> i16 {
    a >> b
}

#[unsafe(no_mangle)]
pub fn ashr_i16_imm(a: i16) -> i16 {
    a >> 5
}

#[unsafe(no_mangle)]
pub fn add_u8(a: u8, b: u8) -> u8 {
    a + b
}

#[unsafe(no_mangle)]
pub fn sub_u8(a: u8, b: u8) -> u8 {
    a - b
}

#[unsafe(no_mangle)]
pub fn mul_u8(a: u8, b: u8) -> u8 {
    a * b
}

#[unsafe(no_mangle)]
pub fn and_u8(a: u8, b: u8) -> u8 {
    a & b
}

#[unsafe(no_mangle)]
pub fn or_u8(a: u8, b: u8) -> u8 {
    a | b
}

#[unsafe(no_mangle)]
pub fn xor_u8(a: u8, b: u8) -> u8 {
    a ^ b
}

#[unsafe(no_mangle)]
pub fn sign_extend_i8_to_i32(a: i8) -> i32 {
    a as i32
}

#[unsafe(no_mangle)]
pub fn zero_extend_u8_to_u32(a: u8) -> u32 {
    a as u32
}

#[unsafe(no_mangle)]
pub fn sign_extend_i16_to_i32(a: i16) -> i32 {
    a as i32
}

#[unsafe(no_mangle)]
pub fn zero_extend_u16_to_u32(a: u16) -> u32 {
    a as u32
}

#[unsafe(no_mangle)]
pub fn mul_u16_widening(a: u16, b: u16) -> u32 {
    (a as u32) * (b as u32)
}
