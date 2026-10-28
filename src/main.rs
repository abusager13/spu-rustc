mod llvm_ir;

use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::PathBuf;
use std::process::{Command, ExitCode};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Emit {
    Assembly,
    Object,
    Executable,
}

#[derive(Debug)]
struct Config {
    input: PathBuf,
    output: PathBuf,
    emit: Emit,
    entry_args: Option<Vec<u32>>,
    target: String,
    rustc: OsString,
    assembler: OsString,
    linker: OsString,
}

struct TempDir(PathBuf);

impl TempDir {
    fn new() -> Result<Self, String> {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map_err(|e| format!("system clock error: {e}"))?
            .as_nanos();
        let path = env::temp_dir().join(format!("spu-rustc-{}-{nonce}", std::process::id()));
        fs::create_dir(&path).map_err(|e| format!("cannot create {}: {e}", path.display()))?;
        Ok(Self(path))
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(message) => {
            eprintln!("spu-rustc: {message}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), String> {
    let config = parse_args(env::args_os().skip(1))?;
    if config.entry_args.is_some() && config.emit != Emit::Executable {
        return Err("--entry-args is only valid with --emit=elf".into());
    }
    let source = fs::read_to_string(&config.input)
        .map_err(|e| format!("cannot read {}: {e}", config.input.display()))?;
    if !source.lines().any(|line| line.trim() == "#![no_std]") {
        return Err("the prototype currently requires a crate-level #![no_std] attribute".into());
    }
    let temp = TempDir::new()?;
    let ir_path = temp.0.join("input.ll");
    let asm_path = temp.0.join("input.s");

    // Rustc is used only as a host-side parser/type checker and LLVM IR frontend.
    // This prototype's lowering pass consumes a deliberately small scalar IR subset.
    let status = Command::new(&config.rustc)
        .arg("--crate-name")
        .arg("spu_program")
        .arg("--crate-type=lib")
        .arg("--edition=2021")
        .arg("--emit=llvm-ir")
        .arg("-Copt-level=1")
        .arg("-Ccodegen-units=1")
        .arg("-Cpanic=abort")
        .arg("-Coverflow-checks=off")
        .arg("-Cdebuginfo=0")
        .arg("-o")
        .arg(&ir_path)
        .arg(&config.input)
        .status()
        .map_err(|e| format!("cannot run rustc {:?}: {e}", config.rustc))?;
    if !status.success() {
        return Err(format!("rustc frontend failed with {status}"));
    }

    let ir = fs::read_to_string(&ir_path)
        .map_err(|e| format!("cannot read Rust compiler IR output: {e}"))?;
    let program = llvm_ir::parse_supported_program(&ir)?;
    if !source_declares_c_export(&source, program.symbol()) {
        return Err(format!(
            "Rust function {} must be declared extern \"C\" and have a no_mangle attribute",
            program.symbol()
        ));
    }
    let assembly = llvm_ir::lower_program_to_spu_assembly(&program)?;

    match config.emit {
        Emit::Assembly => fs::write(&config.output, assembly)
            .map_err(|e| format!("cannot write {}: {e}", config.output.display()))?,
        Emit::Object => {
            fs::write(&asm_path, assembly)
                .map_err(|e| format!("cannot write temporary SPU assembly: {e}"))?;
            let status = Command::new(&config.assembler)
                .arg("-o")
                .arg(&config.output)
                .arg(&asm_path)
                .status()
                .map_err(|e| format!("cannot run SPU assembler {:?}: {e}", config.assembler))?;
            if !status.success() {
                return Err(format!("SPU assembler failed with {status}"));
            }
        }
        Emit::Executable => {
            let runtime_entry = program.runtime_entry_info();
            let entry = program
                .entry_symbol()
                .or_else(|| runtime_entry.map(|_| "_start"));
            let Some(entry) = entry else {
                return Err(
                    "--emit=elf requires a stop-only _start or an i32/bool Rust function".into(),
                );
            };
            if config.entry_args.is_some() && runtime_entry.is_none() {
                return Err("--entry-args cannot be used with a stop-only _start function".into());
            }
            let startup = if let Some((function_symbol, parameter_count)) = runtime_entry {
                if config.entry_args.is_none() && parameter_count != 0 {
                    return Err(format!(
                        "Rust function {function_symbol} takes {parameter_count} i32 arguments; provide them with --entry-args"
                    ));
                }
                let arguments = config.entry_args.as_deref().unwrap_or(&[]);
                if arguments.len() != parameter_count {
                    return Err(format!(
                        "Rust function {function_symbol} takes {parameter_count} i32 arguments, but --entry-args supplied {}",
                        arguments.len()
                    ));
                }
                Some(llvm_ir::lower_runtime_startup(function_symbol, arguments))
            } else {
                None
            };
            fs::write(&asm_path, assembly)
                .map_err(|e| format!("cannot write temporary SPU assembly: {e}"))?;
            let program_object_path = temp.0.join("program.o");
            let status = Command::new(&config.assembler)
                .arg("-o")
                .arg(&program_object_path)
                .arg(&asm_path)
                .status()
                .map_err(|e| format!("cannot run SPU assembler {:?}: {e}", config.assembler))?;
            if !status.success() {
                return Err(format!("SPU assembler failed with {status}"));
            }

            let startup_object_path = if let Some(startup) = startup {
                let startup_asm_path = temp.0.join("startup.s");
                let startup_object_path = temp.0.join("startup.o");
                fs::write(&startup_asm_path, startup)
                    .map_err(|e| format!("cannot write temporary SPU startup assembly: {e}"))?;
                let status = Command::new(&config.assembler)
                    .arg("-o")
                    .arg(&startup_object_path)
                    .arg(&startup_asm_path)
                    .status()
                    .map_err(|e| format!("cannot run SPU assembler {:?}: {e}", config.assembler))?;
                if !status.success() {
                    return Err(format!("SPU startup assembler failed with {status}"));
                }
                Some(startup_object_path)
            } else {
                None
            };

            let mut linker = Command::new(&config.linker);
            linker.arg("-e").arg(entry).arg("-o").arg(&config.output);
            if let Some(startup_object_path) = startup_object_path {
                linker.arg(startup_object_path);
            }
            let status = linker
                .arg(&program_object_path)
                .status()
                .map_err(|e| format!("cannot run SPU linker {:?}: {e}", config.linker))?;
            if !status.success() {
                return Err(format!("SPU linker failed with {status}"));
            }
        }
    }

    eprintln!(
        "spu-rustc: emitted {} for target {} ({})",
        match config.emit {
            Emit::Assembly => "SPU assembly",
            Emit::Object => "SPU ELF object",
            Emit::Executable => "SPU ELF executable",
        },
        config.target,
        config.output.display()
    );
    Ok(())
}

fn parse_args(args: impl Iterator<Item = OsString>) -> Result<Config, String> {
    let mut args = args.peekable();
    let mut input = None;
    let mut output = None;
    let mut emit = Emit::Object;
    let mut entry_args = None;
    let mut target = None;
    let mut rustc = env::var_os("RUSTC").unwrap_or_else(|| OsString::from("rustc"));
    let mut assembler = env::var_os("SPU_AS").unwrap_or_else(|| OsString::from("spu-as"));
    let mut linker = env::var_os("SPU_LD").unwrap_or_else(|| OsString::from("spu-ld"));

    while let Some(arg) = args.next() {
        let arg_text = arg.to_string_lossy();
        if arg == "--help" || arg == "-h" {
            print_help();
            std::process::exit(0);
        } else if arg == "--version" {
            println!(
                "spu-rustc {} (experimental subset)",
                env!("CARGO_PKG_VERSION")
            );
            std::process::exit(0);
        } else if arg == "--target" {
            target = Some(next_value(&mut args, "--target")?);
        } else if let Some(value) = arg_text.strip_prefix("--target=") {
            target = Some(OsString::from(value));
        } else if arg == "--emit" {
            emit = parse_emit(&next_value(&mut args, "--emit")?)?;
        } else if let Some(value) = arg_text.strip_prefix("--emit=") {
            emit = parse_emit(&OsString::from(value))?;
        } else if arg == "--entry-args" {
            entry_args = Some(parse_entry_args(&next_value(&mut args, "--entry-args")?)?);
        } else if let Some(value) = arg_text.strip_prefix("--entry-args=") {
            entry_args = Some(parse_entry_args(&OsString::from(value))?);
        } else if arg == "-o" {
            output = Some(PathBuf::from(next_value(&mut args, "-o")?));
        } else if arg == "--rustc" {
            rustc = next_value(&mut args, "--rustc")?;
        } else if arg == "--assembler" {
            assembler = next_value(&mut args, "--assembler")?;
        } else if arg == "--linker" {
            linker = next_value(&mut args, "--linker")?;
        } else if arg_text.starts_with('-') {
            return Err(format!("unrecognized option {arg_text:?}; see --help"));
        } else if input.is_none() {
            input = Some(PathBuf::from(arg));
        } else {
            return Err(format!("unexpected extra input {:?}", arg_text));
        }
    }

    let target = target.ok_or("missing required --target spu-sony-ps3")?;
    if target != "spu-sony-ps3" {
        return Err(format!(
            "unsupported target {:?}; this prototype supports only spu-sony-ps3",
            target.to_string_lossy()
        ));
    }
    let input = input.ok_or("missing Rust source file; see --help")?;
    let output = output.unwrap_or_else(|| {
        let extension = match emit {
            Emit::Assembly => "s",
            Emit::Object => "o",
            Emit::Executable => "elf",
        };
        input.with_extension(extension)
    });

    Ok(Config {
        input,
        output,
        emit,
        entry_args,
        target: target.to_string_lossy().into_owned(),
        rustc,
        assembler,
        linker,
    })
}

fn next_value(args: &mut impl Iterator<Item = OsString>, option: &str) -> Result<OsString, String> {
    args.next()
        .ok_or_else(|| format!("missing value after {option}"))
}

fn parse_emit(value: &OsString) -> Result<Emit, String> {
    match value.to_string_lossy().as_ref() {
        "asm" => Ok(Emit::Assembly),
        "obj" => Ok(Emit::Object),
        "elf" => Ok(Emit::Executable),
        other => Err(format!(
            "unsupported output kind {other:?}; choose asm, obj, or elf"
        )),
    }
}

fn parse_entry_args(value: &OsString) -> Result<Vec<u32>, String> {
    let text = value.to_string_lossy();
    if text.trim().is_empty() {
        return Ok(Vec::new());
    }
    let mut arguments = Vec::new();
    for (index, raw) in text.split(',').enumerate() {
        let raw = raw.trim();
        if raw.is_empty() {
            return Err(format!(
                "--entry-args has an empty value at position {}",
                index + 1
            ));
        }
        let value = if let Some(hex) = raw.strip_prefix("0x") {
            u32::from_str_radix(hex, 16).map_err(|_| {
                format!(
                    "--entry-args value {raw:?} at position {} is not a 32-bit word",
                    index + 1
                )
            })?
        } else {
            let decimal = raw.parse::<i64>().map_err(|_| {
                format!(
                    "--entry-args value {raw:?} at position {} is not a 32-bit word",
                    index + 1
                )
            })?;
            if decimal < i32::MIN as i64 || decimal > u32::MAX as i64 {
                return Err(format!(
                    "--entry-args value {raw:?} at position {} is outside the 32-bit range",
                    index + 1
                ));
            }
            decimal as u32
        };
        arguments.push(value);
    }
    if arguments.len() > 72 {
        return Err(format!(
            "--entry-args supports at most 72 register-passed words; found {}",
            arguments.len()
        ));
    }
    Ok(arguments)
}

fn print_help() {
    println!(
        "Usage: spu-rustc --target spu-sony-ps3 [--emit obj|asm|elf] [--entry-args WORD,...] [-o OUTPUT] [--rustc PATH] [--assembler PATH] [--linker PATH] INPUT.rs\n\n\
         Compiles a restricted #![no_std] Rust function through a limited LLVM IR subset.\n\
         rustc is used as the host-side frontend; spu-as emits an EM_SPU object.\n\
         --emit=elf links a stop-only _start or a scalar function through minimal startup.\n\
         --entry-args supplies comma-separated decimal or hexadecimal 32-bit words\n\
         for the scalar function's SPU ABI argument registers.\n\
         This is an experimental proof of concept, not a rustc target specification."
    );
}

fn source_declares_c_export(source: &str, symbol: &str) -> bool {
    let signature = format!("extern \"C\" fn {symbol}");
    let lines: Vec<&str> = source.lines().collect();
    for (index, line) in lines.iter().enumerate() {
        if !line.contains(&signature) {
            continue;
        }
        return lines[..index]
            .iter()
            .rev()
            .take_while(|line| {
                let line = line.trim();
                line.is_empty() || line.starts_with("//") || line.starts_with("#[")
            })
            .any(|line| line.contains("no_mangle"));
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_signed_decimal_and_hex_entry_words() {
        assert_eq!(
            parse_entry_args(&OsString::from("0x1234,-1,4294967295")).unwrap(),
            vec![0x1234, u32::MAX, u32::MAX]
        );
    }

    #[test]
    fn accepts_an_empty_entry_argument_list() {
        assert_eq!(
            parse_entry_args(&OsString::from("")).unwrap(),
            Vec::<u32>::new()
        );
    }

    #[test]
    fn rejects_invalid_and_out_of_range_entry_words() {
        assert!(parse_entry_args(&OsString::from("1,wat"))
            .unwrap_err()
            .contains("not a 32-bit word"));
        assert!(parse_entry_args(&OsString::from("4294967296"))
            .unwrap_err()
            .contains("outside the 32-bit range"));
        assert!(parse_entry_args(&OsString::from("1,"))
            .unwrap_err()
            .contains("empty value"));
    }

    #[test]
    fn rejects_more_entry_words_than_register_arguments() {
        let words = std::iter::repeat_n("1", 73).collect::<Vec<_>>().join(",");
        assert!(parse_entry_args(&OsString::from(words))
            .unwrap_err()
            .contains("at most 72"));
    }
}
