#![no_std]

#[cfg(not(test))]
use core::ffi::c_char;
#[cfg(not(test))]
use core::slice;

#[cfg(not(test))]
const DEFAULT_IMAGE_PATH: &[u8] = b"/app_home/scalar.elf\0";
const MAX_ARGUMENTS: usize = 4;
const MAX_ARGC: i32 = 2 + MAX_ARGUMENTS as i32;
#[cfg(not(test))]
const USAGE_ERROR: i32 = 64;

#[cfg(not(test))]
unsafe extern "C" {
    fn spu_loader_run(
        path: *const c_char,
        thread_arguments: *const u64,
        exit_status: *mut i32,
    ) -> i32;
}

fn parse_u64(bytes: &[u8]) -> Option<u64> {
    let (radix, digits) = if let Some(digits) = bytes.strip_prefix(b"0x") {
        (16_u64, digits)
    } else if let Some(digits) = bytes.strip_prefix(b"0X") {
        (16_u64, digits)
    } else {
        (10_u64, bytes)
    };
    if digits.is_empty() {
        return None;
    }

    let mut value = 0_u64;
    for byte in digits {
        let digit = match byte {
            b'0'..=b'9' => u64::from(*byte - b'0'),
            b'a'..=b'f' => u64::from(*byte - b'a' + 10),
            b'A'..=b'F' => u64::from(*byte - b'A' + 10),
            _ => return None,
        };
        if digit >= radix {
            return None;
        }
        value = value.checked_mul(radix)?.checked_add(digit)?;
    }
    Some(value)
}

fn thread_argument_count(argc: i32) -> Option<usize> {
    if argc < 0 || argc > MAX_ARGC {
        return None;
    }
    Some(if argc <= 2 { 0 } else { (argc - 2) as usize })
}

#[cfg(not(test))]
unsafe fn c_argument_bytes<'a>(argument: *const c_char) -> Option<&'a [u8]> {
    if argument.is_null() {
        return None;
    }
    let mut length = 0;
    while *argument.add(length) != 0 {
        length += 1;
    }
    Some(slice::from_raw_parts(argument.cast(), length))
}

/// PSL1GHT's PPU CRT calls this C ABI entry point.
#[cfg(not(test))]
#[no_mangle]
pub extern "C" fn main(argc: i32, argv: *const *const c_char) -> i32 {
    let Some(argument_count) = thread_argument_count(argc) else {
        return USAGE_ERROR;
    };
    if argc > 1 && argv.is_null() {
        return USAGE_ERROR;
    }

    // argv[1] selects the image. With no path argument, load the default image
    // from /app_home/scalar.elf. Following the path, accept up to four decimal
    // or 0x-prefixed u64 values for PSL1GHT's SPU thread argument structure.
    let path = if argc >= 2 && !argv.is_null() {
        let arg = unsafe { *argv.add(1) };
        if arg.is_null() {
            return USAGE_ERROR;
        }
        arg
    } else {
        DEFAULT_IMAGE_PATH.as_ptr().cast()
    };

    let mut thread_arguments = [0_u64; MAX_ARGUMENTS];
    for (index, slot) in thread_arguments.iter_mut().enumerate().take(argument_count) {
        let argument = unsafe { *argv.add(index + 2) };
        let Some(bytes) = (unsafe { c_argument_bytes(argument) }) else {
            return USAGE_ERROR;
        };
        let Some(value) = parse_u64(bytes) else {
            return USAGE_ERROR;
        };
        *slot = value;
    }

    let mut exit_status = 0;
    let error = unsafe { spu_loader_run(path, thread_arguments.as_ptr(), &mut exit_status) };
    if error != 0 {
        return error;
    }

    exit_status
}

#[cfg(test)]
extern crate std;

#[cfg(test)]
mod tests {
    use super::{parse_u64, thread_argument_count};

    #[test]
    fn accepts_up_to_four_thread_arguments_after_the_image_path() {
        std::assert_eq!(thread_argument_count(1), Some(0));
        std::assert_eq!(thread_argument_count(2), Some(0));
        std::assert_eq!(thread_argument_count(6), Some(4));
    }

    #[test]
    fn rejects_invalid_thread_argument_counts() {
        std::assert_eq!(thread_argument_count(-1), None);
        std::assert_eq!(thread_argument_count(7), None);
    }

    #[test]
    fn parses_decimal_and_hex_thread_arguments() {
        std::assert_eq!(parse_u64(b"42"), Some(42));
        std::assert_eq!(
            parse_u64(b"0x123456789abcdef0"),
            Some(0x1234_5678_9abc_def0)
        );
        std::assert_eq!(parse_u64(b"0XFF"), Some(255));
        std::assert_eq!(parse_u64(b"18446744073709551615"), Some(u64::MAX));
    }

    #[test]
    fn rejects_invalid_or_out_of_range_thread_arguments() {
        std::assert_eq!(parse_u64(b""), None);
        std::assert_eq!(parse_u64(b"0x"), None);
        std::assert_eq!(parse_u64(b"-1"), None);
        std::assert_eq!(parse_u64(b"1z"), None);
        std::assert_eq!(parse_u64(b"0x10000000000000000"), None);
        std::assert_eq!(parse_u64(b"18446744073709551616"), None);
    }
}

#[cfg(not(test))]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}
