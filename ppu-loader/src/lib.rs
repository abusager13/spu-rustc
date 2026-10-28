#![no_std]

use core::ffi::c_char;

const DEFAULT_IMAGE_PATH: &[u8] = b"/app_home/scalar.elf\0";

unsafe extern "C" {
    fn spu_loader_run(path: *const c_char, exit_status: *mut i32) -> i32;
}

/// PSL1GHT's PPU CRT calls this C ABI entry point.
#[no_mangle]
pub extern "C" fn main(argc: i32, argv: *const *const c_char) -> i32 {
    // A PS3 launch can use the conventional argv path or the default path for
    // an image placed at /app_home/scalar.elf alongside the loader.
    let path = if argc >= 2 && !argv.is_null() {
        let arg = unsafe { *argv.add(1) };
        if arg.is_null() {
            return 64;
        }
        arg
    } else {
        DEFAULT_IMAGE_PATH.as_ptr().cast()
    };

    let mut exit_status = 0;
    let error = unsafe { spu_loader_run(path, &mut exit_status) };
    if error != 0 {
        return error;
    }

    exit_status
}

#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}
