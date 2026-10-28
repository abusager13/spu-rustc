use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

fn assert_in_order(output: &str, instructions: &[&str], context: &str) {
    let mut offset = 0;
    for instruction in instructions {
        let remaining = &output[offset..];
        let Some(position) = remaining.find(instruction) else {
            panic!("missing or out-of-order {instruction:?} in {context}:\n{output}");
        };
        offset += position + instruction.len();
    }
}

#[test]
fn emits_big_endian_spu_objects_for_no_std_i32_operations() {
    let assembler = env::var_os("SPU_AS").unwrap_or_else(|| "spu-as".into());
    if Command::new(&assembler).arg("--version").output().is_err() {
        if env::var_os("SPU_REQUIRE_E2E").is_some() {
            panic!("SPU end-to-end test required, but SPU_AS is unavailable");
        }
        eprintln!("skipping SPU end-to-end test: SPU_AS is unavailable");
        return;
    }

    let rustc = env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    if Command::new(&rustc).arg("--version").output().is_err() {
        if env::var_os("SPU_REQUIRE_E2E").is_some() {
            panic!("SPU end-to-end test required, but RUSTC is unavailable");
        }
        eprintln!("skipping SPU end-to-end test: RUSTC is unavailable");
        return;
    }

    let objdump = env::var_os("SPU_OBJDUMP").unwrap_or_else(|| "spu-objdump".into());
    if Command::new(&objdump).arg("--version").output().is_err() {
        if env::var_os("SPU_REQUIRE_E2E").is_some() {
            panic!("SPU end-to-end test required, but SPU_OBJDUMP is unavailable");
        }
        eprintln!("skipping SPU end-to-end test: SPU_OBJDUMP is unavailable");
        return;
    }

    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let temp = env::temp_dir().join(format!("spu-rustc-e2e-{}-{nonce}", std::process::id()));
    fs::create_dir(&temp).unwrap();

    let cases = [
        ("add_u32", "a\t$3,$3,$4"),
        ("sub_u32", "sf\t$3,$4,$3"),
        ("mul_u32", "mpyu\t$3"),
        ("mul_i32", "mpyu\t$3"),
        ("mul_constant_u32", "mpyu\t$4,$3,$4"),
        ("and_u32", "and\t$3,$3,$4"),
        ("or_u32", "or\t$3,$3,$4"),
        ("xor_u32", "xor\t$3,$3,$4"),
        ("increment_u32", "ai\t$3,$3,1"),
        ("and_low_byte", "andi\t$3,$3,255"),
        ("or_low_bit", "ori\t$3,$3,1"),
        ("xor_low_bit", "xori\t$3,$3,1"),
        ("sum3_u32", "a\t$6,$3,$4"),
        ("identity_u32", "bi\t$0"),
        ("constant_u32", "il\t$3,42"),
        ("wide_constant_u32", "ilhu\t$3,4660"),
        ("add_large_constant", "il\t$4,4096"),
        ("add_wide_constant", "ilhu\t$4,4660"),
        ("sum8_u32", "a\t$11,$3,$4"),
        ("wrapping_shl_u32", "shl\t$3,$3,$5"),
        ("wrapping_shr_u32", "rotm\t$3,$3,$5"),
        ("wrapping_shr_i32", "rotma\t$3,$3,$5"),
        ("wrapping_shl_const_u32", "shli\t$3,$3,5"),
        ("wrapping_shr_const_u32", "rotmi\t$3,$3,-5"),
        ("wrapping_shr_const_i32", "rotmai\t$3,$3,-5"),
        ("rotate_left_u32", "rot\t$3,$3,$4"),
        ("rotate_right_u32", "rot\t$3,$3,$4"),
        ("rotate_left_const_u32", "roti\t$3,$3,5"),
        ("rotate_right_const_u32", "roti\t$3,$3,27"),
        ("leading_zeros_u32", "clz\t$3,$3"),
        ("leading_ones_u32", "clz\t$3,$4"),
        ("trailing_zeros_u32", "ceqi\t$4,$3,0"),
        ("trailing_ones_u32", "ceqi\t$5,$4,0"),
        ("count_ones_u32", "cntb\t$3,$3"),
        ("wrapping_abs_i32", "rotmai\t$4,$3,-31"),
        ("min_i32", "selb\t$3,$4,$3,$5"),
        ("max_i32", "selb\t$3,$3,$4,$5"),
        ("min_u32", "selb\t$3,$4,$3,$5"),
        ("max_u32", "selb\t$3,$3,$4,$5"),
        ("saturating_add_u32", "clgt\t$3,$3,$5"),
        ("select_i32", "selb\t$3"),
        ("select_computed_i32", "selb\t$3"),
        ("cmp_eq_u32", "ceq\t$3,$3,$4"),
        ("cmp_ne_u32", "nor\t$3,$3,$3"),
        ("cmp_slt_i32", "cgt\t$3,$4,$3"),
        ("cmp_sgt_i32", "cgt\t$3,$3,$4"),
        ("cmp_sle_i32", "nor\t$3,$3,$3"),
        ("cmp_sge_i32", "nor\t$3,$3,$3"),
        ("cmp_ult_u32", "clgt\t$3,$4,$3"),
        ("cmp_ugt_u32", "clgt\t$3,$3,$4"),
        ("cmp_ule_u32", "nor\t$3,$3,$3"),
        ("cmp_uge_u32", "nor\t$3,$3,$3"),
    ];
    for (name, mnemonic) in cases {
        let source = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("examples")
            .join(format!("{name}.rs"));
        let object = temp.join(format!("{name}.o"));
        let result = Command::new(env!("CARGO_BIN_EXE_spu-rustc"))
            .arg("--target=spu-sony-ps3")
            .arg("--emit=obj")
            .arg("-o")
            .arg(&object)
            .arg("--rustc")
            .arg(&rustc)
            .arg("--assembler")
            .arg(&assembler)
            .arg(&source)
            .output()
            .unwrap();
        assert!(
            result.status.success(),
            "compilation failed for {name}:\n{}\n{}",
            String::from_utf8_lossy(&result.stdout),
            String::from_utf8_lossy(&result.stderr)
        );

        let bytes = fs::read(&object).unwrap();
        assert_eq!(&bytes[0..6], b"\x7fELF\x01\x02", "{name} ELF class/endian");
        assert_eq!(
            &bytes[18..20],
            b"\x00\x17",
            "{name} ELF machine must be EM_SPU"
        );

        let disassembly = Command::new(&objdump)
            .arg("-dr")
            .arg(&object)
            .output()
            .unwrap();
        assert!(
            disassembly.status.success(),
            "spu-objdump failed for {name}"
        );
        let disassembly = String::from_utf8_lossy(&disassembly.stdout);
        assert!(
            disassembly.contains(mnemonic),
            "expected {mnemonic:?} in {name} object:\n{disassembly}"
        );
        if name == "sum3_u32" {
            assert_in_order(
                &disassembly,
                &["a\t$6,$3,$4", "lnop", "a\t$3,$5,$6", "bi\t$0"],
                "sum3_u32",
            );
        }
        if name == "mul_u32" {
            assert_in_order(
                &disassembly,
                &[
                    "mpyh\t$5,$4,$3",
                    "lnop",
                    "mpyh\t$6,$3,$4",
                    "lnop",
                    "mpyu\t$3,$4,$3",
                    "lnop",
                    "a\t$5,$5,$6",
                    "lnop",
                    "a\t$3,$3,$5",
                    "bi\t$0",
                ],
                "mul_u32",
            );
        }
        if name == "mul_constant_u32" {
            assert_in_order(
                &disassembly,
                &[
                    "ilhu\t$4,4660",
                    "lnop",
                    "iohl\t$4,22136",
                    "lnop",
                    "mpyh\t$5,$3,$4",
                    "lnop",
                    "mpyh\t$6,$4,$3",
                    "lnop",
                    "mpyu\t$4,$3,$4",
                    "lnop",
                    "a\t$5,$5,$6",
                    "lnop",
                    "a\t$4,$4,$5",
                    "lnop",
                    "or\t$3,$4,$4",
                ],
                "mul_constant_u32",
            );
        }
        if name == "sum8_u32" {
            assert_in_order(
                &disassembly,
                &[
                    "a\t$11,$3,$4",
                    "lnop",
                    "a\t$12,$5,$11",
                    "lnop",
                    "a\t$11,$6,$12",
                    "lnop",
                    "a\t$3,$10,$12",
                    "bi\t$0",
                ],
                "sum8_u32",
            );
        }
        if name == "wrapping_shr_u32" || name == "wrapping_shr_i32" {
            let shift = if name == "wrapping_shr_i32" {
                "rotma"
            } else {
                "rotm"
            };
            assert_in_order(
                &disassembly,
                &[
                    "andi\t$5,$4,31",
                    "sfi\t$5,$5,0",
                    &format!("{shift}\t$3,$3,$5"),
                ],
                name,
            );
        }
        if name == "rotate_right_u32" {
            assert_in_order(
                &disassembly,
                &["sfi\t$4,$4,0", "lnop", "rot\t$3,$3,$4", "bi\t$0"],
                "rotate_right_u32",
            );
        }
        if name == "count_ones_u32" {
            assert_in_order(
                &disassembly,
                &["cntb\t$3,$3", "sumb\t$3,$3,$3", "xshw\t$3,$3"],
                "count_ones_u32",
            );
        }
        if name == "trailing_zeros_u32" {
            assert_in_order(
                &disassembly,
                &[
                    "ceqi\t$4,$3,0",
                    "sfi\t$5,$3,0",
                    "and\t$5,$3,$5",
                    "clz\t$3,$5",
                    "sfi\t$3,$3,31",
                    "andi\t$4,$4,33",
                    "a\t$3,$3,$4",
                ],
                "trailing_zeros_u32",
            );
        }
        if name == "leading_ones_u32" {
            assert_in_order(
                &disassembly,
                &["xori\t$4,$3,-1", "clz\t$3,$4"],
                "leading_ones_u32",
            );
        }
        if name == "trailing_ones_u32" {
            assert_in_order(
                &disassembly,
                &[
                    "xori\t$4,$3,-1",
                    "ceqi\t$5,$4,0",
                    "sfi\t$6,$4,0",
                    "and\t$6,$4,$6",
                    "clz\t$3,$6",
                    "sfi\t$3,$3,31",
                    "andi\t$5,$5,33",
                    "a\t$3,$3,$5",
                ],
                "trailing_ones_u32",
            );
        }
        if name == "wrapping_abs_i32" {
            assert_in_order(
                &disassembly,
                &["rotmai\t$4,$3,-31", "xor\t$3,$3,$4", "sf\t$3,$4,$3"],
                "wrapping_abs_i32",
            );
        }
        if name == "min_i32" || name == "max_i32" {
            assert_in_order(&disassembly, &["cgt\t$5,$4,$3", "lnop", "selb\t$3"], name);
        }
        if name == "min_u32" || name == "max_u32" {
            assert_in_order(&disassembly, &["clgt\t$5,$4,$3", "lnop", "selb\t$3"], name);
        }
        if name == "saturating_add_u32" {
            assert_in_order(
                &disassembly,
                &[
                    "a\t$5,$3,$4",
                    "lnop",
                    "clgt\t$3,$3,$5",
                    "lnop",
                    "or\t$3,$5,$3",
                ],
                name,
            );
        }
        if name == "select_i32" || name == "select_computed_i32" {
            let selection = disassembly.find("selb\t$3").unwrap();
            let prefix = &disassembly[..selection];
            assert!(
                prefix.contains("cgt\t"),
                "select condition compare missing in {name}:\n{disassembly}"
            );
            assert!(
                !prefix.contains("andi\t"),
                "select condition was normalized to 0/1 before selb in {name}:\n{disassembly}"
            );
        }
        if name.starts_with("cmp_") {
            assert!(
                disassembly.contains("andi\t$3,$3,1"),
                "Rust bool return was not normalized to 0 or 1 in {name}:\n{disassembly}"
            );
        }
        if name == "wide_constant_u32" {
            assert_in_order(
                &disassembly,
                &["ilhu\t$3,4660", "lnop", "iohl\t$3,22136", "bi\t$0"],
                "wide_constant_u32",
            );
        }
        if name == "add_large_constant" {
            assert_in_order(
                &disassembly,
                &[
                    "il\t$4,4096",
                    "lnop",
                    "a\t$4,$3,$4",
                    "lnop",
                    "or\t$3,$4,$4",
                    "bi\t$0",
                ],
                "add_large_constant",
            );
        }
        if name == "add_wide_constant" {
            assert_in_order(
                &disassembly,
                &[
                    "ilhu\t$4,4660",
                    "lnop",
                    "iohl\t$4,22136",
                    "lnop",
                    "a\t$4,$3,$4",
                    "lnop",
                    "or\t$3,$4,$4",
                    "bi\t$0",
                ],
                "add_wide_constant",
            );
        }
        assert!(
            disassembly.contains("bi\t$0"),
            "missing SPU return in {name}"
        );
    }

    fs::remove_dir_all(temp).unwrap();
}

#[test]
fn links_a_no_std_stop_entry_as_an_spu_elf_executable() {
    let assembler = env::var_os("SPU_AS").unwrap_or_else(|| "spu-as".into());
    let linker = env::var_os("SPU_LD").unwrap_or_else(|| "spu-ld".into());
    let objdump = env::var_os("SPU_OBJDUMP").unwrap_or_else(|| "spu-objdump".into());
    let rustc = env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    for (name, program) in [
        ("SPU_AS", &assembler),
        ("SPU_LD", &linker),
        ("SPU_OBJDUMP", &objdump),
        ("RUSTC", &rustc),
    ] {
        if Command::new(program).arg("--version").output().is_err() {
            if env::var_os("SPU_REQUIRE_E2E").is_some() {
                panic!("SPU end-to-end test required, but {name} is unavailable");
            }
            eprintln!("skipping SPU executable test: {name} is unavailable");
            return;
        }
    }

    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let temp = env::temp_dir().join(format!("spu-rustc-exe-{}-{nonce}", std::process::id()));
    fs::create_dir(&temp).unwrap();
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("examples/stop_entry.rs");
    let executable = temp.join("stop.elf");
    let result = Command::new(env!("CARGO_BIN_EXE_spu-rustc"))
        .arg("--target=spu-sony-ps3")
        .arg("--emit=elf")
        .arg("-o")
        .arg(&executable)
        .arg("--rustc")
        .arg(&rustc)
        .arg("--assembler")
        .arg(&assembler)
        .arg("--linker")
        .arg(&linker)
        .arg(&source)
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "SPU executable link failed:\n{}\n{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );

    let bytes = fs::read(&executable).unwrap();
    assert_eq!(&bytes[0..6], b"\x7fELF\x01\x02", "ELF class/endian");
    assert_eq!(&bytes[16..18], b"\x00\x02", "ELF type must be ET_EXEC");
    assert_eq!(&bytes[18..20], b"\x00\x17", "ELF machine must be EM_SPU");
    assert!(
        u16::from_be_bytes([bytes[44], bytes[45]]) > 0,
        "missing program headers"
    );

    let disassembly = Command::new(&objdump)
        .arg("-d")
        .arg(&executable)
        .output()
        .unwrap();
    assert!(
        disassembly.status.success(),
        "spu-objdump failed for stop entry"
    );
    let disassembly = String::from_utf8_lossy(&disassembly.stdout);
    assert!(disassembly.contains("<_start>"), "missing _start symbol");
    assert!(
        disassembly.contains("stop"),
        "missing native SPU stop instruction"
    );

    fs::remove_dir_all(temp).unwrap();
}

#[test]
fn links_a_scalar_entry_with_local_store_startup_and_mailbox_return() {
    let assembler = env::var_os("SPU_AS").unwrap_or_else(|| "spu-as".into());
    let linker = env::var_os("SPU_LD").unwrap_or_else(|| "spu-ld".into());
    let objdump = env::var_os("SPU_OBJDUMP").unwrap_or_else(|| "spu-objdump".into());
    let rustc = env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    for (name, program) in [
        ("SPU_AS", &assembler),
        ("SPU_LD", &linker),
        ("SPU_OBJDUMP", &objdump),
        ("RUSTC", &rustc),
    ] {
        if Command::new(program).arg("--version").output().is_err() {
            if env::var_os("SPU_REQUIRE_E2E").is_some() {
                panic!("SPU end-to-end test required, but {name} is unavailable");
            }
            eprintln!("skipping scalar SPU executable test: {name} is unavailable");
            return;
        }
    }

    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let temp = env::temp_dir().join(format!(
        "spu-rustc-scalar-exe-{}-{nonce}",
        std::process::id()
    ));
    fs::create_dir(&temp).unwrap();
    let source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("examples/scalar_entry.rs");
    let executable = temp.join("scalar.elf");
    let result = Command::new(env!("CARGO_BIN_EXE_spu-rustc"))
        .arg("--target=spu-sony-ps3")
        .arg("--emit=elf")
        .arg("-o")
        .arg(&executable)
        .arg("--rustc")
        .arg(&rustc)
        .arg("--assembler")
        .arg(&assembler)
        .arg("--linker")
        .arg(&linker)
        .arg(&source)
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "scalar SPU executable link failed:\n{}\n{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );

    let bytes = fs::read(&executable).unwrap();
    assert_eq!(&bytes[0..6], b"\x7fELF\x01\x02", "ELF class/endian");
    assert_eq!(&bytes[16..18], b"\x00\x02", "ELF type must be ET_EXEC");
    assert_eq!(&bytes[18..20], b"\x00\x17", "ELF machine must be EM_SPU");
    assert!(u16::from_be_bytes([bytes[44], bytes[45]]) > 0);
    let read_be_u32 =
        |offset: usize| u32::from_be_bytes(bytes[offset..offset + 4].try_into().unwrap());
    let program_header_offset = read_be_u32(28) as usize;
    let program_header_size = u16::from_be_bytes([bytes[42], bytes[43]]) as usize;
    let program_header_count = u16::from_be_bytes([bytes[44], bytes[45]]) as usize;
    let load_header = (0..program_header_count)
        .map(|index| program_header_offset + index * program_header_size)
        .find(|offset| read_be_u32(*offset) == 1)
        .expect("missing PT_LOAD segment");
    assert_eq!(
        read_be_u32(load_header + 8),
        0,
        "local-store image must start at 0"
    );
    let load_file_size = read_be_u32(load_header + 16);
    let load_memory_size = read_be_u32(load_header + 20);
    let load_flags = read_be_u32(load_header + 24);
    assert!(load_file_size <= load_memory_size);
    assert!(
        load_memory_size <= 0x40000,
        "local-store segment exceeds 256 KiB"
    );
    assert_eq!(
        load_flags & 0x5,
        0x5,
        "SPU text segment must be readable and executable"
    );

    let disassembly = Command::new(&objdump)
        .arg("-d")
        .arg(&executable)
        .output()
        .unwrap();
    assert!(
        disassembly.status.success(),
        "spu-objdump failed for scalar entry"
    );
    let disassembly = String::from_utf8_lossy(&disassembly.stdout);
    assert!(
        disassembly.contains("<_start>"),
        "missing _start:\n{disassembly}"
    );
    assert!(
        disassembly.contains("<scalar_entry>"),
        "missing Rust function:\n{disassembly}"
    );
    assert_in_order(
        &disassembly,
        &[
            "ilhu\t$1,4",
            "il\t$2,0",
            "brsl\t$0,",
            "wrch\t$ch28,$3",
            "stop",
            "il\t$3,42",
            "bi\t$0",
        ],
        "scalar-entry startup and return protocol",
    );

    let add_source = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("examples/add_u32.rs");
    let add_executable = temp.join("add-entry.elf");
    let result = Command::new(env!("CARGO_BIN_EXE_spu-rustc"))
        .arg("--target=spu-sony-ps3")
        .arg("--emit=elf")
        .arg("--entry-args=0x12345678,0x5678")
        .arg("-o")
        .arg(&add_executable)
        .arg("--rustc")
        .arg(&rustc)
        .arg("--assembler")
        .arg(&assembler)
        .arg("--linker")
        .arg(&linker)
        .arg(&add_source)
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "argumentful SPU executable link failed:\n{}\n{}",
        String::from_utf8_lossy(&result.stdout),
        String::from_utf8_lossy(&result.stderr)
    );
    let add_bytes = fs::read(&add_executable).unwrap();
    assert_eq!(&add_bytes[0..6], b"\x7fELF\x01\x02", "ELF class/endian");
    assert_eq!(&add_bytes[16..18], b"\x00\x02", "ELF type must be ET_EXEC");
    assert_eq!(
        &add_bytes[18..20],
        b"\x00\x17",
        "ELF machine must be EM_SPU"
    );
    let disassembly = Command::new(&objdump)
        .arg("-d")
        .arg(&add_executable)
        .output()
        .unwrap();
    assert!(
        disassembly.status.success(),
        "spu-objdump failed for argumentful scalar entry"
    );
    let disassembly = String::from_utf8_lossy(&disassembly.stdout);
    assert!(
        disassembly.contains("<add_u32>"),
        "missing add_u32:\n{disassembly}"
    );
    assert_in_order(
        &disassembly,
        &[
            "ilhu\t$1,4",
            "il\t$2,0",
            "ilhu\t$3,4660",
            "iohl\t$3,22136",
            "il\t$4,22136",
            "brsl\t$0,",
            "wrch\t$ch28,$3",
            "stop",
            "a\t$3,$3,$4",
            "bi\t$0",
        ],
        "argumentful scalar-entry startup and Rust addition",
    );

    let mismatch = Command::new(env!("CARGO_BIN_EXE_spu-rustc"))
        .arg("--target=spu-sony-ps3")
        .arg("--emit=elf")
        .arg("--entry-args=0x1234")
        .arg("-o")
        .arg(temp.join("bad-args.elf"))
        .arg("--rustc")
        .arg(&rustc)
        .arg("--assembler")
        .arg(&assembler)
        .arg("--linker")
        .arg(&linker)
        .arg(&add_source)
        .output()
        .unwrap();
    assert!(
        !mismatch.status.success(),
        "wrong entry argument count accepted"
    );
    assert!(
        String::from_utf8_lossy(&mismatch.stderr)
            .contains("takes 2 i32 arguments, but --entry-args supplied 1"),
        "wrong argument count should report the required and supplied counts:\n{}",
        String::from_utf8_lossy(&mismatch.stderr)
    );

    fs::remove_dir_all(temp).unwrap();
}
