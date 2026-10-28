#![no_std]

#[unsafe(no_mangle)]
pub extern "C" fn cmp_sgt_i32(lhs: i32, rhs: i32) -> bool {
    lhs > rhs
}
