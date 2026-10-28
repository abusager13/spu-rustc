#![no_std]

mod spu {
    #[inline(always)]
    pub unsafe fn stop<const CODE: u16>() -> ! {
        unsafe {
            core::arch::asm!(
                "stop {code}",
                code = const CODE,
                options(noreturn, nomem, nostack)
            );
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn _start() -> ! {
    unsafe { spu::stop::<0>() }
}
