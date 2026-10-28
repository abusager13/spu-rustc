use std::collections::{BTreeSet, HashMap};

#[derive(Debug, Eq, PartialEq)]
pub struct Function {
    name: String,
    params: Vec<String>,
    instructions: Vec<Instruction>,
    returned: Operand,
    return_type: ReturnType,
}

#[derive(Debug, Eq, PartialEq)]
pub enum Program {
    Scalar(Function),
    StopEntry(String),
}

#[derive(Debug, Eq, PartialEq)]
struct Instruction {
    result: String,
    op: Operation,
    lhs: Operand,
    rhs: Operand,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum Operand {
    Value(String),
    Constant(i32),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ReturnType {
    I32,
    Bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Operation {
    Binary(BinaryOp),
    Unary(UnaryOp),
    Compare(Predicate),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum UnaryOp {
    CountLeadingZeros,
    CountTrailingZeros,
    CountOnes,
    WrappingAbs,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum BinaryOp {
    Add,
    Sub,
    Mul,
    And,
    Or,
    Xor,
    Shl,
    LShr,
    AShr,
    RotateLeft,
    RotateRight,
    SignedMin,
    SignedMax,
    UnsignedMin,
    UnsignedMax,
    UnsignedSaturatingAdd,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Predicate {
    Eq,
    Ne,
    SignedGt,
    SignedGe,
    SignedLt,
    SignedLe,
    UnsignedGt,
    UnsignedGe,
    UnsignedLt,
    UnsignedLe,
}

pub fn parse_single_i32_binary_function(module: &str) -> Result<Function, String> {
    let signature = single_definition(module)?;
    let at = signature
        .find('@')
        .ok_or("LLVM function name is missing @")?;
    if !signature[..at].trim_end().ends_with("i32") {
        return Err("only functions returning i32 are supported".into());
    }
    let function = parse_scalar_function(module)?;
    if function.return_type != ReturnType::I32 {
        return Err("only functions returning i32 are supported".into());
    }
    Ok(function)
}

fn parse_scalar_function(module: &str) -> Result<Function, String> {
    let signature = single_definition(module)?;
    if !signature.contains('{') {
        return Err("multi-line LLVM function signatures are not supported".into());
    }
    let (name, params, return_type) = parse_signature(signature)?;
    if params.len() > 72 {
        return Err(format!(
            "SPU ABI register lowering supports at most 72 i32 parameters; found {}",
            params.len()
        ));
    }
    let mut value_types = params
        .iter()
        .map(|param| (param.clone(), ReturnType::I32))
        .collect::<HashMap<_, _>>();
    let mut instructions = Vec::new();
    let mut returned = None;
    let mut saw_return = false;
    let mut in_body = false;
    for line in module.lines() {
        let trimmed = line.trim();
        if !in_body {
            if line.trim_start().starts_with("define ") {
                in_body = true;
            }
            continue;
        }
        if trimmed.starts_with('}') {
            break;
        }
        if trimmed.is_empty() || trimmed.starts_with(';') || trimmed.ends_with(':') {
            continue;
        }
        if let Some(value) = trimmed.strip_prefix("ret ") {
            if saw_return {
                return Err("multiple return instructions are not supported".into());
            }
            let (type_text, value) = value
                .split_once(' ')
                .ok_or("LLVM return value is missing")?;
            let observed_type = parse_return_type(type_text)?;
            if observed_type != return_type {
                return Err(format!(
                    "LLVM return type {type_text} does not match function return type {return_type:?}"
                ));
            }
            let operand = parse_return_operand(value.trim(), return_type)?;
            if let Operand::Value(name) = &operand {
                if value_types.get(name) != Some(&return_type) {
                    return Err(format!(
                        "return value {name} is undefined or has the wrong LLVM type"
                    ));
                }
            }
            returned = Some(operand);
            saw_return = true;
            continue;
        }
        if let Some((result, expression)) = trimmed.split_once(" = ") {
            if saw_return {
                return Err("instructions after the return are not supported".into());
            }
            let instruction = parse_instruction(result.trim(), expression.trim())?;
            for operand in [&instruction.lhs, &instruction.rhs] {
                if let Operand::Value(name) = operand {
                    match value_types.get(name) {
                        Some(ReturnType::I32) => {}
                        Some(ReturnType::Bool) => {
                            return Err(format!(
                            "LLVM value {name} is i1; bool values cannot be used as i32 operands"
                        ))
                        }
                        None => {
                            return Err(format!("LLVM value {name} is used before it is defined"))
                        }
                    }
                }
            }
            if params.iter().any(|param| param == &instruction.result)
                || instructions
                    .iter()
                    .any(|prior: &Instruction| prior.result == instruction.result)
            {
                return Err(format!("duplicate LLVM result {}", instruction.result));
            }
            let output_type = match instruction.op {
                Operation::Binary(_) => ReturnType::I32,
                Operation::Unary(_) => ReturnType::I32,
                Operation::Compare(_) => ReturnType::Bool,
            };
            if output_type == ReturnType::Bool && return_type != ReturnType::Bool {
                return Err("integer comparison results may only be returned as Rust bool".into());
            }
            value_types.insert(instruction.result.clone(), output_type);
            instructions.push(instruction);
            continue;
        }
        return Err(format!("unsupported LLVM IR instruction: {trimmed}"));
    }
    let returned = returned.ok_or("function has no return")?;
    Ok(Function {
        name,
        params,
        instructions,
        returned,
        return_type,
    })
}

pub fn parse_supported_program(module: &str) -> Result<Program, String> {
    let signature = single_definition(module)?;
    let at = signature
        .find('@')
        .ok_or("LLVM function name is missing @")?;
    let return_type = signature[..at].trim_end();
    if return_type.ends_with("i32") {
        return Ok(Program::Scalar(parse_single_i32_binary_function(module)?));
    }
    if return_type.ends_with("i1") {
        return Ok(Program::Scalar(parse_scalar_function(module)?));
    }
    if return_type.ends_with("void") {
        return Ok(Program::StopEntry(parse_stop_entry(module)?));
    }
    Err("only i32, bool, and the _start stop entry are supported".into())
}

fn single_definition(module: &str) -> Result<&str, String> {
    let definitions: Vec<&str> = module
        .lines()
        .filter(|line| line.trim_start().starts_with("define "))
        .collect();
    if definitions.len() != 1 {
        return Err(format!(
            "expected one defined function in LLVM IR; found {}",
            definitions.len()
        ));
    }
    Ok(definitions[0].trim())
}

fn parse_stop_entry(module: &str) -> Result<String, String> {
    let signature = single_definition(module)?;
    if !signature.contains('{') {
        return Err("multi-line LLVM function signatures are not supported".into());
    }
    let at = signature
        .find('@')
        .ok_or("LLVM function name is missing @")?;
    if !signature[..at].trim_end().ends_with("void") {
        return Err("the stop entry must return void".into());
    }
    let open = signature[at..]
        .find('(')
        .map(|index| at + index)
        .ok_or("LLVM function parameter list is missing")?;
    let close = signature[open..]
        .find(')')
        .map(|index| open + index)
        .ok_or("LLVM function parameter list is unterminated")?;
    let name = &signature[at + 1..open];
    if name != "_start" {
        return Err("an SPU executable entry must be named _start".into());
    }
    if !signature[open + 1..close].trim().is_empty() {
        return Err("the SPU _start entry must not have parameters".into());
    }

    let mut saw_stop = false;
    let mut saw_unreachable = false;
    let mut in_body = false;
    for line in module.lines() {
        let trimmed = line.trim();
        if !in_body {
            if line.trim_start().starts_with("define ") {
                in_body = true;
            }
            continue;
        }
        if trimmed.starts_with('}') {
            break;
        }
        if trimmed.is_empty() || trimmed.starts_with(';') || trimmed.ends_with(':') {
            continue;
        }
        if is_stop_inline_asm(trimmed) {
            if saw_stop {
                return Err("multiple stop instructions are not supported".into());
            }
            saw_stop = true;
        } else if trimmed == "unreachable" {
            saw_unreachable = true;
        } else {
            return Err(format!(
                "unsupported LLVM IR stop-entry instruction: {trimmed}"
            ));
        }
    }
    if !saw_stop || !saw_unreachable {
        return Err("_start must contain a non-returning SPU stop 0 instruction".into());
    }
    Ok(name.to_owned())
}

fn is_stop_inline_asm(line: &str) -> bool {
    let Some((_, tail)) = line.split_once("asm sideeffect") else {
        return false;
    };
    let tail = tail.trim_start();
    let tail = tail
        .strip_prefix("inteldialect ")
        .or_else(|| tail.strip_prefix("attdialect "))
        .unwrap_or(tail);
    tail.starts_with("\"stop 0\",") && tail.contains("()")
}

fn parse_signature(signature: &str) -> Result<(String, Vec<String>, ReturnType), String> {
    let at = signature
        .find('@')
        .ok_or("LLVM function name is missing @")?;
    let return_type = signature[..at]
        .split_whitespace()
        .last()
        .ok_or("LLVM function return type is missing")?;
    let return_type = parse_return_type(return_type)?;
    let open = signature[at..]
        .find('(')
        .map(|index| at + index)
        .ok_or("LLVM function parameter list is missing")?;
    let close = signature[open..]
        .find(')')
        .map(|index| open + index)
        .ok_or("LLVM function parameter list is unterminated")?;
    let name = &signature[at + 1..open];
    if !is_asm_identifier(name) {
        return Err(format!("unsupported SPU symbol name {name:?}"));
    }
    let raw_params = signature[open + 1..close].trim();
    let mut params = Vec::new();
    if !raw_params.is_empty() {
        for param in raw_params.split(',') {
            let param = param.trim();
            if !param.starts_with("i32 ") {
                return Err(format!("only named i32 parameters are supported: {param}"));
            }
            let name = param
                .rfind('%')
                .map(|index| &param[index..])
                .ok_or_else(|| format!("unnamed LLVM parameter is unsupported: {param}"))?;
            if !is_llvm_local(name) {
                return Err(format!("unsupported LLVM parameter name {name:?}"));
            }
            if params.iter().any(|prior| prior == name) {
                return Err(format!("duplicate LLVM parameter name {name}"));
            }
            params.push(name.to_owned());
        }
    }
    if params.len() > 72 {
        return Err("parameters passed on the stack are not supported".into());
    }
    Ok((name.to_owned(), params, return_type))
}

fn parse_return_type(value: &str) -> Result<ReturnType, String> {
    match value {
        "i32" => Ok(ReturnType::I32),
        "i1" => Ok(ReturnType::Bool),
        other => Err(format!("unsupported LLVM scalar type {other:?}")),
    }
}

fn parse_return_operand(value: &str, return_type: ReturnType) -> Result<Operand, String> {
    if return_type == ReturnType::Bool {
        return match value {
            "true" | "1" => Ok(Operand::Constant(1)),
            "false" | "0" => Ok(Operand::Constant(0)),
            _ => parse_operand(value),
        };
    }
    parse_operand(value)
}

fn parse_instruction(result: &str, expression: &str) -> Result<Instruction, String> {
    if !is_llvm_local(result) {
        return Err(format!("unsupported LLVM result name {result:?}"));
    }
    if let Some((op, operand)) = parse_ctlz(expression)? {
        return Ok(Instruction {
            result: result.to_owned(),
            op: Operation::Unary(op),
            lhs: operand,
            rhs: Operand::Constant(0),
        });
    }
    if let Some(operand) = parse_cttz(expression)? {
        return Ok(Instruction {
            result: result.to_owned(),
            op: Operation::Unary(UnaryOp::CountTrailingZeros),
            lhs: operand,
            rhs: Operand::Constant(0),
        });
    }
    if let Some(operand) = parse_ctpop(expression)? {
        return Ok(Instruction {
            result: result.to_owned(),
            op: Operation::Unary(UnaryOp::CountOnes),
            lhs: operand,
            rhs: Operand::Constant(0),
        });
    }
    if let Some(operand) = parse_wrapping_abs(expression)? {
        return Ok(Instruction {
            result: result.to_owned(),
            op: Operation::Unary(UnaryOp::WrappingAbs),
            lhs: operand,
            rhs: Operand::Constant(0),
        });
    }
    if let Some((op, lhs, rhs)) = parse_funnel_shift(expression)? {
        return Ok(Instruction {
            result: result.to_owned(),
            op: Operation::Binary(op),
            lhs,
            rhs,
        });
    }
    if let Some((op, lhs, rhs)) = parse_minmax(expression)? {
        return Ok(Instruction {
            result: result.to_owned(),
            op: Operation::Binary(op),
            lhs,
            rhs,
        });
    }
    if let Some((lhs, rhs)) = parse_unsigned_saturating_add(expression)? {
        return Ok(Instruction {
            result: result.to_owned(),
            op: Operation::Binary(BinaryOp::UnsignedSaturatingAdd),
            lhs,
            rhs,
        });
    }
    let mut fields = expression.split_whitespace();
    let mnemonic = fields.next().unwrap_or_default();
    let operation = if mnemonic == "icmp" {
        let predicate = match fields.next().unwrap_or_default() {
            "eq" => Predicate::Eq,
            "ne" => Predicate::Ne,
            "sgt" => Predicate::SignedGt,
            "sge" => Predicate::SignedGe,
            "slt" => Predicate::SignedLt,
            "sle" => Predicate::SignedLe,
            "ugt" => Predicate::UnsignedGt,
            "uge" => Predicate::UnsignedGe,
            "ult" => Predicate::UnsignedLt,
            "ule" => Predicate::UnsignedLe,
            other => return Err(format!("unsupported LLVM integer predicate {other:?}")),
        };
        if fields.next() != Some("i32") {
            return Err("LLVM comparisons currently require i32 operands".into());
        }
        Operation::Compare(predicate)
    } else {
        let op = match mnemonic {
            "add" => BinaryOp::Add,
            "sub" => BinaryOp::Sub,
            "mul" => BinaryOp::Mul,
            "and" => BinaryOp::And,
            "or" => BinaryOp::Or,
            "xor" => BinaryOp::Xor,
            "shl" => BinaryOp::Shl,
            "lshr" => BinaryOp::LShr,
            "ashr" => BinaryOp::AShr,
            other => return Err(format!("unsupported LLVM operation {other:?}")),
        };
        if fields.next() != Some("i32") {
            return Err("only i32 binary operands are supported".into());
        }
        Operation::Binary(op)
    };
    let operands = fields.collect::<Vec<_>>().join(" ");
    if operands.is_empty() {
        return Err("LLVM operation operands are missing".into());
    }
    let (lhs, rhs) = operands
        .split_once(',')
        .ok_or("LLVM operation needs two operands")?;
    let lhs = parse_operand(lhs.trim())?;
    let rhs = parse_operand(rhs.trim())?;
    Ok(Instruction {
        result: result.to_owned(),
        op: operation,
        lhs,
        rhs,
    })
}

fn parse_operand(value: &str) -> Result<Operand, String> {
    if is_llvm_local(value) {
        return Ok(Operand::Value(value.to_owned()));
    }
    let parsed = if let Some(hex) = value.strip_prefix("0x") {
        u64::from_str_radix(hex, 16)
            .ok()
            .filter(|value| *value <= u32::MAX as u64)
            .map(|value| value as u32 as i32)
    } else {
        value
            .parse::<i64>()
            .ok()
            .filter(|value| (i32::MIN as i64..=u32::MAX as i64).contains(value))
            .map(|value| value as u32 as i32)
    };
    parsed
        .map(Operand::Constant)
        .ok_or_else(|| format!("unsupported i32 operand {value:?}"))
}

fn parse_funnel_shift(expression: &str) -> Result<Option<(BinaryOp, Operand, Operand)>, String> {
    let (intrinsic, op) = if expression.contains("@llvm.fshl.i32") {
        ("@llvm.fshl.i32", BinaryOp::RotateLeft)
    } else if expression.contains("@llvm.fshr.i32") {
        ("@llvm.fshr.i32", BinaryOp::RotateRight)
    } else {
        return Ok(None);
    };
    let name_start = expression
        .find(intrinsic)
        .ok_or("LLVM funnel-shift intrinsic name is missing")?;
    let open = expression[name_start + intrinsic.len()..]
        .find('(')
        .map(|offset| name_start + intrinsic.len() + offset)
        .ok_or("LLVM funnel-shift argument list is missing")?;
    let close = expression[open + 1..]
        .find(')')
        .map(|offset| open + 1 + offset)
        .ok_or("LLVM funnel-shift argument list is unterminated")?;
    let arguments = expression[open + 1..close]
        .split(',')
        .map(|argument| {
            let fields = argument.split_whitespace().collect::<Vec<_>>();
            if !fields.contains(&"i32") {
                return Err("LLVM funnel-shift arguments must be i32".to_owned());
            }
            let value = fields
                .last()
                .ok_or_else(|| "LLVM funnel-shift argument is missing".to_owned())?;
            parse_operand(value)
        })
        .collect::<Result<Vec<_>, _>>()?;
    if arguments.len() != 3 {
        return Err(format!(
            "LLVM funnel-shift intrinsic requires three operands; found {}",
            arguments.len()
        ));
    }
    if arguments[0] != arguments[1] {
        return Err("only rotate forms with identical funnel-shift inputs are supported".into());
    }
    Ok(Some((op, arguments[0].clone(), arguments[2].clone())))
}

fn parse_minmax(expression: &str) -> Result<Option<(BinaryOp, Operand, Operand)>, String> {
    let Some((intrinsic, op)) = [
        ("@llvm.smin.i32", BinaryOp::SignedMin),
        ("@llvm.smax.i32", BinaryOp::SignedMax),
        ("@llvm.umin.i32", BinaryOp::UnsignedMin),
        ("@llvm.umax.i32", BinaryOp::UnsignedMax),
    ]
    .into_iter()
    .find(|(intrinsic, _)| expression.contains(intrinsic)) else {
        return Ok(None);
    };
    let name_start = expression
        .find(intrinsic)
        .ok_or("LLVM min/max intrinsic name is missing")?;
    let open = expression[name_start + intrinsic.len()..]
        .find('(')
        .map(|offset| name_start + intrinsic.len() + offset)
        .ok_or("LLVM min/max argument list is missing")?;
    let close = expression[open + 1..]
        .find(')')
        .map(|offset| open + 1 + offset)
        .ok_or("LLVM min/max argument list is unterminated")?;
    let arguments = expression[open + 1..close]
        .split(',')
        .map(|argument| {
            let fields = argument.split_whitespace().collect::<Vec<_>>();
            if !fields.contains(&"i32") {
                return Err("LLVM min/max arguments must be i32".to_owned());
            }
            let value = fields
                .last()
                .ok_or_else(|| "LLVM min/max argument is missing".to_owned())?;
            parse_operand(value)
        })
        .collect::<Result<Vec<_>, _>>()?;
    if arguments.len() != 2 {
        return Err(format!(
            "LLVM min/max intrinsic requires two operands; found {}",
            arguments.len()
        ));
    }
    Ok(Some((op, arguments[0].clone(), arguments[1].clone())))
}

fn parse_unsigned_saturating_add(expression: &str) -> Result<Option<(Operand, Operand)>, String> {
    let intrinsic = "@llvm.uadd.sat.i32";
    let Some(name_start) = expression.find(intrinsic) else {
        return Ok(None);
    };
    let open = expression[name_start + intrinsic.len()..]
        .find('(')
        .map(|offset| name_start + intrinsic.len() + offset)
        .ok_or("LLVM saturating-add argument list is missing")?;
    let close = expression[open + 1..]
        .find(')')
        .map(|offset| open + 1 + offset)
        .ok_or("LLVM saturating-add argument list is unterminated")?;
    let arguments = expression[open + 1..close]
        .split(',')
        .map(|argument| {
            let fields = argument.split_whitespace().collect::<Vec<_>>();
            if !fields.contains(&"i32") {
                return Err("LLVM saturating-add arguments must be i32".to_owned());
            }
            let value = fields
                .last()
                .ok_or_else(|| "LLVM saturating-add argument is missing".to_owned())?;
            parse_operand(value)
        })
        .collect::<Result<Vec<_>, _>>()?;
    if arguments.len() != 2 {
        return Err(format!(
            "LLVM saturating-add intrinsic requires two operands; found {}",
            arguments.len()
        ));
    }
    Ok(Some((arguments[0].clone(), arguments[1].clone())))
}

fn parse_ctlz(expression: &str) -> Result<Option<(UnaryOp, Operand)>, String> {
    let intrinsic = "@llvm.ctlz.i32";
    let Some(name_start) = expression.find(intrinsic) else {
        return Ok(None);
    };
    let open = expression[name_start + intrinsic.len()..]
        .find('(')
        .map(|offset| name_start + intrinsic.len() + offset)
        .ok_or("LLVM ctlz argument list is missing")?;
    let close = expression[open + 1..]
        .find(')')
        .map(|offset| open + 1 + offset)
        .ok_or("LLVM ctlz argument list is unterminated")?;
    let arguments = expression[open + 1..close]
        .split(',')
        .map(|argument| {
            let fields = argument.split_whitespace().collect::<Vec<_>>();
            let ty = if fields.contains(&"i32") {
                "i32"
            } else if fields.contains(&"i1") {
                "i1"
            } else {
                return Err("LLVM ctlz argument type is unsupported".to_owned());
            };
            let value = fields
                .last()
                .ok_or_else(|| "LLVM ctlz argument is missing".to_owned())?;
            Ok((ty, *value))
        })
        .collect::<Result<Vec<_>, String>>()?;
    if arguments.len() != 2 || arguments[0].0 != "i32" || arguments[1].0 != "i1" {
        return Err("LLVM ctlz requires an i32 value and an i1 zero-undef flag".into());
    }
    if arguments[1].1 != "false" {
        return Err("only defined-zero LLVM ctlz semantics are supported".into());
    }
    Ok(Some((
        UnaryOp::CountLeadingZeros,
        parse_operand(arguments[0].1)?,
    )))
}

fn parse_cttz(expression: &str) -> Result<Option<Operand>, String> {
    let intrinsic = "@llvm.cttz.i32";
    let Some(name_start) = expression.find(intrinsic) else {
        return Ok(None);
    };
    let open = expression[name_start + intrinsic.len()..]
        .find('(')
        .map(|offset| name_start + intrinsic.len() + offset)
        .ok_or("LLVM cttz argument list is missing")?;
    let close = expression[open + 1..]
        .find(')')
        .map(|offset| open + 1 + offset)
        .ok_or("LLVM cttz argument list is unterminated")?;
    let arguments = expression[open + 1..close]
        .split(',')
        .map(|argument| {
            let fields = argument.split_whitespace().collect::<Vec<_>>();
            let ty = if fields.contains(&"i32") {
                "i32"
            } else if fields.contains(&"i1") {
                "i1"
            } else {
                return Err("LLVM cttz argument type is unsupported".to_owned());
            };
            let value = fields
                .last()
                .ok_or_else(|| "LLVM cttz argument is missing".to_owned())?;
            Ok((ty, *value))
        })
        .collect::<Result<Vec<_>, String>>()?;
    if arguments.len() != 2 || arguments[0].0 != "i32" || arguments[1].0 != "i1" {
        return Err("LLVM cttz requires an i32 value and an i1 zero-undef flag".into());
    }
    if arguments[1].1 != "false" {
        return Err("only defined-zero LLVM cttz semantics are supported".into());
    }
    Ok(Some(parse_operand(arguments[0].1)?))
}

fn parse_ctpop(expression: &str) -> Result<Option<Operand>, String> {
    let intrinsic = "@llvm.ctpop.i32";
    let Some(name_start) = expression.find(intrinsic) else {
        return Ok(None);
    };
    let open = expression[name_start + intrinsic.len()..]
        .find('(')
        .map(|offset| name_start + intrinsic.len() + offset)
        .ok_or("LLVM ctpop argument list is missing")?;
    let close = expression[open + 1..]
        .find(')')
        .map(|offset| open + 1 + offset)
        .ok_or("LLVM ctpop argument list is unterminated")?;
    let fields = expression[open + 1..close]
        .split_whitespace()
        .collect::<Vec<_>>();
    if !fields.contains(&"i32") {
        return Err("LLVM ctpop requires an i32 value".into());
    }
    let value = fields.last().ok_or("LLVM ctpop argument is missing")?;
    Ok(Some(parse_operand(value)?))
}

fn parse_wrapping_abs(expression: &str) -> Result<Option<Operand>, String> {
    let intrinsic = "@llvm.abs.i32";
    let Some(name_start) = expression.find(intrinsic) else {
        return Ok(None);
    };
    let open = expression[name_start + intrinsic.len()..]
        .find('(')
        .map(|offset| name_start + intrinsic.len() + offset)
        .ok_or("LLVM abs argument list is missing")?;
    let close = expression[open + 1..]
        .find(')')
        .map(|offset| open + 1 + offset)
        .ok_or("LLVM abs argument list is unterminated")?;
    let arguments = expression[open + 1..close]
        .split(',')
        .map(|argument| {
            let fields = argument.split_whitespace().collect::<Vec<_>>();
            let ty = if fields.contains(&"i32") {
                "i32"
            } else if fields.contains(&"i1") {
                "i1"
            } else {
                return Err("LLVM abs argument type is unsupported".to_owned());
            };
            let value = fields
                .last()
                .ok_or_else(|| "LLVM abs argument is missing".to_owned())?;
            Ok((ty, *value))
        })
        .collect::<Result<Vec<_>, String>>()?;
    if arguments.len() != 2 || arguments[0].0 != "i32" || arguments[1].0 != "i1" {
        return Err("LLVM abs requires an i32 value and an i1 poison flag".into());
    }
    if arguments[1].1 != "false" {
        return Err("only defined-overflow LLVM abs semantics are supported".into());
    }
    Ok(Some(parse_operand(arguments[0].1)?))
}

pub fn lower_to_spu_assembly(function: &Function) -> Result<String, String> {
    // Preserve inputs in ABI argument registers and keep computed values in
    // caller-saved registers. A last-use pass lets linear code reuse dead temps.
    let mut reg_for = HashMap::new();
    for (index, param) in function.params.iter().enumerate() {
        reg_for.insert(param.clone(), index + 3);
    }
    let first_temp = function.params.len() + 3;
    let mut last_use = HashMap::new();
    for (index, instruction) in function.instructions.iter().enumerate() {
        for operand in [&instruction.lhs, &instruction.rhs] {
            if let Operand::Value(value) = operand {
                last_use.insert(value.clone(), index);
            }
        }
    }
    if let Operand::Value(value) = &function.returned {
        last_use.insert(value.clone(), function.instructions.len());
    }

    let mut operations = Vec::with_capacity(function.instructions.len() + 1);
    let mut free_temps = BTreeSet::new();
    let mut next_temp = first_temp;
    for (index, instruction) in function.instructions.iter().enumerate() {
        let needs_constant_register = match (instruction.op, &instruction.lhs, &instruction.rhs) {
            (
                Operation::Binary(BinaryOp::RotateLeft | BinaryOp::RotateRight),
                Operand::Value(_),
                Operand::Constant(_),
            ) => false,
            (Operation::Binary(op), Operand::Value(_), Operand::Constant(value)) => {
                is_minmax(op)
                    || op == BinaryOp::UnsignedSaturatingAdd
                    || !immediate_is_encodable(op, *value, false)
            }
            (Operation::Binary(op), Operand::Constant(value), Operand::Value(_)) => {
                is_minmax(op)
                    || op == BinaryOp::UnsignedSaturatingAdd
                    || !immediate_is_encodable(op, *value, true)
            }
            (Operation::Compare(_), Operand::Value(_), Operand::Constant(_))
            | (Operation::Compare(_), Operand::Constant(_), Operand::Value(_)) => true,
            _ => false,
        };
        let returns_this_value = index + 1 == function.instructions.len()
            && matches!(&function.returned, Operand::Value(value) if value == &instruction.result);
        let dst = if returns_this_value && !needs_constant_register {
            3
        } else if let Some(reg) = free_temps.pop_first() {
            reg
        } else if next_temp < 80 {
            let reg = next_temp;
            next_temp += 1;
            reg
        } else {
            return Err(format!(
                "linear code needs more than the available caller-saved SPU registers (through $79)"
            ));
        };
        match (&instruction.lhs, &instruction.rhs) {
            (Operand::Value(lhs), Operand::Value(rhs)) => {
                let rhs_name = rhs;
                let lhs_reg = *reg_for
                    .get(lhs)
                    .ok_or_else(|| format!("unknown SPU value {lhs}"))?;
                let rhs_reg = *reg_for
                    .get(rhs)
                    .ok_or_else(|| format!("unknown SPU value {rhs}"))?;
                match instruction.op {
                    Operation::Unary(UnaryOp::CountLeadingZeros) => {
                        operations.push(format!("clz ${dst},${lhs_reg}"));
                    }
                    Operation::Unary(UnaryOp::CountTrailingZeros) => {
                        operations.extend(lower_trailing_zeros(
                            dst,
                            lhs_reg,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Unary(UnaryOp::CountOnes) => {
                        operations.extend([
                            format!("cntb ${dst},${lhs_reg}"),
                            format!("sumb ${dst},${dst},${dst}"),
                            format!("xshw ${dst},${dst}"),
                        ]);
                    }
                    Operation::Unary(UnaryOp::WrappingAbs) => {
                        operations.extend(lower_wrapping_abs(
                            dst,
                            lhs_reg,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(op @ (BinaryOp::LShr | BinaryOp::AShr)) => {
                        let count_is_dead = last_use.get(rhs_name) == Some(&index);
                        operations.extend(lower_variable_shift(
                            op,
                            dst,
                            lhs_reg,
                            rhs_reg,
                            count_is_dead,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(BinaryOp::RotateRight) => {
                        let count_is_dead = last_use.get(rhs_name) == Some(&index);
                        operations.extend(lower_variable_rotate_right(
                            dst,
                            lhs_reg,
                            rhs_reg,
                            count_is_dead,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(op) if is_minmax(op) => {
                        operations.extend(lower_minmax(
                            op,
                            dst,
                            lhs_reg,
                            rhs_reg,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(BinaryOp::UnsignedSaturatingAdd) => {
                        operations.extend(lower_unsigned_saturating_add(
                            dst,
                            lhs_reg,
                            rhs_reg,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(op) => {
                        let (mut lhs, mut rhs) = (lhs_reg, rhs_reg);
                        if matches!(
                            op,
                            BinaryOp::Add | BinaryOp::And | BinaryOp::Or | BinaryOp::Xor
                        ) && lhs > rhs
                        {
                            std::mem::swap(&mut lhs, &mut rhs);
                        }
                        if op == BinaryOp::Mul {
                            operations.extend(lower_multiply(
                                dst,
                                lhs,
                                rhs,
                                &mut next_temp,
                                &mut free_temps,
                            )?);
                        } else {
                            operations.push(lower_binary_register(op, dst, lhs, rhs)?);
                        }
                    }
                    Operation::Compare(predicate) => {
                        operations.extend(lower_compare(predicate, dst, lhs_reg, rhs_reg));
                    }
                }
            }
            (Operand::Value(value), Operand::Constant(constant)) => {
                let source = *reg_for
                    .get(value)
                    .ok_or_else(|| format!("unknown SPU value {value}"))?;
                match instruction.op {
                    Operation::Unary(UnaryOp::CountLeadingZeros) => {
                        operations.push(format!("clz ${dst},${source}"));
                    }
                    Operation::Unary(UnaryOp::CountTrailingZeros) => {
                        operations.extend(lower_trailing_zeros(
                            dst,
                            source,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Unary(UnaryOp::CountOnes) => {
                        operations.extend([
                            format!("cntb ${dst},${source}"),
                            format!("sumb ${dst},${dst},${dst}"),
                            format!("xshw ${dst},${dst}"),
                        ]);
                    }
                    Operation::Unary(UnaryOp::WrappingAbs) => {
                        operations.extend(lower_wrapping_abs(
                            dst,
                            source,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(op @ (BinaryOp::RotateLeft | BinaryOp::RotateRight)) => {
                        operations.push(lower_rotate_immediate(op, dst, source, *constant));
                    }
                    Operation::Binary(op) if immediate_is_encodable(op, *constant, false) => {
                        operations.push(lower_immediate(op, dst, source, *constant, false)?);
                    }
                    Operation::Binary(op)
                        if matches!(op, BinaryOp::Shl | BinaryOp::LShr | BinaryOp::AShr) =>
                    {
                        return Err(format!(
                            "constant shift amount {constant} is outside the SPU 0..31 immediate range"
                        ));
                    }
                    Operation::Binary(BinaryOp::Mul) => {
                        operations.extend(materialize_i32(dst, *constant));
                        operations.extend(lower_multiply(
                            dst,
                            source,
                            dst,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(op) if is_minmax(op) => {
                        operations.extend(materialize_i32(dst, *constant));
                        operations.extend(lower_minmax(
                            op,
                            dst,
                            source,
                            dst,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(BinaryOp::UnsignedSaturatingAdd) => {
                        operations.extend(materialize_i32(dst, *constant));
                        operations.extend(lower_unsigned_saturating_add(
                            dst,
                            source,
                            dst,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(op) => {
                        operations
                            .extend(lower_constant_binary(op, dst, source, *constant, false)?);
                    }
                    Operation::Compare(predicate) => {
                        operations.extend(materialize_i32(dst, *constant));
                        operations.extend(lower_compare(predicate, dst, source, dst));
                    }
                }
            }
            (Operand::Constant(constant), Operand::Value(value)) => {
                let source = *reg_for
                    .get(value)
                    .ok_or_else(|| format!("unknown SPU value {value}"))?;
                match instruction.op {
                    Operation::Unary(_) => {
                        return Err("unary SPU instruction received a constant value".into())
                    }
                    Operation::Binary(op @ (BinaryOp::RotateLeft | BinaryOp::RotateRight)) => {
                        operations.extend(materialize_i32(dst, *constant));
                        if op == BinaryOp::RotateLeft {
                            operations.push(format!("rot ${dst},${dst},${source}"));
                        } else {
                            let count_is_dead = last_use.get(value) == Some(&index);
                            operations.extend(lower_variable_rotate_right(
                                dst,
                                dst,
                                source,
                                count_is_dead,
                                &mut next_temp,
                                &mut free_temps,
                            )?);
                        }
                    }
                    Operation::Binary(op) if is_minmax(op) => {
                        operations.extend(materialize_i32(dst, *constant));
                        operations.extend(lower_minmax(
                            op,
                            dst,
                            dst,
                            source,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(BinaryOp::UnsignedSaturatingAdd) => {
                        operations.extend(materialize_i32(dst, *constant));
                        operations.extend(lower_unsigned_saturating_add(
                            dst,
                            dst,
                            source,
                            &mut next_temp,
                            &mut free_temps,
                        )?);
                    }
                    Operation::Binary(op) if immediate_is_encodable(op, *constant, true) => {
                        operations.push(lower_immediate(op, dst, source, *constant, true)?);
                    }
                    Operation::Binary(op) => {
                        if matches!(op, BinaryOp::Shl | BinaryOp::LShr | BinaryOp::AShr) {
                            operations.extend(materialize_i32(dst, *constant));
                            if op == BinaryOp::Shl {
                                operations.push(lower_binary_register(op, dst, dst, source)?);
                            } else {
                                let count_is_dead = last_use.get(value) == Some(&index);
                                operations.extend(lower_variable_shift(
                                    op,
                                    dst,
                                    dst,
                                    source,
                                    count_is_dead,
                                    &mut next_temp,
                                    &mut free_temps,
                                )?);
                            }
                        } else if op == BinaryOp::Mul {
                            operations.extend(materialize_i32(dst, *constant));
                            operations.extend(lower_multiply(
                                dst,
                                dst,
                                source,
                                &mut next_temp,
                                &mut free_temps,
                            )?);
                        } else {
                            operations
                                .extend(lower_constant_binary(op, dst, source, *constant, true)?);
                        }
                    }
                    Operation::Compare(predicate) => {
                        operations.extend(materialize_i32(dst, *constant));
                        operations.extend(lower_compare(predicate, dst, dst, source));
                    }
                }
            }
            (Operand::Constant(lhs), Operand::Constant(rhs)) => match instruction.op {
                Operation::Unary(UnaryOp::CountLeadingZeros) => {
                    operations.extend(materialize_i32(dst, (*lhs as u32).leading_zeros() as i32));
                }
                Operation::Unary(UnaryOp::CountTrailingZeros) => {
                    operations.extend(materialize_i32(dst, (*lhs as u32).trailing_zeros() as i32));
                }
                Operation::Unary(UnaryOp::CountOnes) => {
                    operations.extend(materialize_i32(dst, (*lhs as u32).count_ones() as i32));
                }
                Operation::Unary(UnaryOp::WrappingAbs) => {
                    operations.extend(materialize_i32(dst, lhs.wrapping_abs()));
                }
                Operation::Compare(predicate) => {
                    let result = evaluate_predicate(predicate, *lhs, *rhs) as i32;
                    operations.extend(materialize_i32(dst, result));
                }
                Operation::Binary(BinaryOp::RotateLeft) => {
                    operations.extend(materialize_i32(
                        dst,
                        (*lhs as u32).rotate_left(*rhs as u32) as i32,
                    ));
                }
                Operation::Binary(BinaryOp::RotateRight) => {
                    operations.extend(materialize_i32(
                        dst,
                        (*lhs as u32).rotate_right(*rhs as u32) as i32,
                    ));
                }
                Operation::Binary(BinaryOp::SignedMin) => {
                    operations.extend(materialize_i32(dst, (*lhs).min(*rhs)));
                }
                Operation::Binary(BinaryOp::SignedMax) => {
                    operations.extend(materialize_i32(dst, (*lhs).max(*rhs)));
                }
                Operation::Binary(BinaryOp::UnsignedMin) => {
                    operations.extend(materialize_i32(
                        dst,
                        ((*lhs as u32).min(*rhs as u32)) as i32,
                    ));
                }
                Operation::Binary(BinaryOp::UnsignedMax) => {
                    operations.extend(materialize_i32(
                        dst,
                        ((*lhs as u32).max(*rhs as u32)) as i32,
                    ));
                }
                Operation::Binary(BinaryOp::UnsignedSaturatingAdd) => {
                    operations.extend(materialize_i32(
                        dst,
                        ((*lhs as u32).saturating_add(*rhs as u32)) as i32,
                    ));
                }
                Operation::Binary(_) => {
                    return Err("constant-only binary operations are not supported".into())
                }
            },
        }
        reg_for.insert(instruction.result.clone(), dst);

        for operand in [&instruction.lhs, &instruction.rhs] {
            if let Operand::Value(value) = operand {
                if last_use.get(value) == Some(&index) {
                    if let Some(reg) = reg_for.get(value).copied() {
                        if reg >= first_temp && reg < 80 {
                            free_temps.insert(reg);
                        }
                    }
                }
            }
        }
        if last_use.get(&instruction.result).is_none() && dst >= first_temp && dst < 80 {
            free_temps.insert(dst);
        }
    }

    let returned = match &function.returned {
        Operand::Value(value) => *reg_for
            .get(value)
            .ok_or_else(|| format!("unknown SPU return value {value}"))?,
        Operand::Constant(value) => {
            operations.extend(materialize_i32(3, *value));
            3
        }
    };
    if returned != 3 {
        operations.push(format!("or $3,${returned},${returned}"));
    }
    let mut body = String::new();
    for (index, operation) in operations.iter().enumerate() {
        body.push_str(&format!("  {operation}\n"));
        // The supported scalar arithmetic and logic instructions issue on
        // SPU pipe 0. Fill pipe 1 when another pipe-0 operation follows.
        // The final operation pairs with `bi`, which issues on pipe 1.
        if index + 1 != operations.len() {
            body.push_str("  lnop\n");
        }
    }
    body.push_str("  bi $0\n");
    Ok(format!(
        ".text\n.p2align 3\n.globl {}\n.type {},@function\n{}:\n{}.size {},.-{}\n",
        function.name, function.name, function.name, body, function.name, function.name
    ))
}

fn lower_immediate(
    op: BinaryOp,
    destination: usize,
    source: usize,
    value: i32,
    constant_is_lhs: bool,
) -> Result<String, String> {
    let Some(immediate) = immediate_value(op, value, constant_is_lhs) else {
        return Err(format!(
            "SPU {op:?} cannot encode constant {value} as a signed 10-bit immediate"
        ));
    };
    let instruction = match op {
        BinaryOp::Add | BinaryOp::Sub => "ai",
        BinaryOp::Mul => return Err("SPU multiply has no immediate form".into()),
        BinaryOp::And => "andi",
        BinaryOp::Or => "ori",
        BinaryOp::Xor => "xori",
        BinaryOp::Shl => "shli",
        BinaryOp::LShr => "rotmi",
        BinaryOp::AShr => "rotmai",
        BinaryOp::RotateLeft | BinaryOp::RotateRight => {
            return Err("SPU rotate immediates use the dedicated lowering path".into())
        }
        BinaryOp::SignedMin
        | BinaryOp::SignedMax
        | BinaryOp::UnsignedMin
        | BinaryOp::UnsignedMax => return Err("SPU min/max use compare and select lowering".into()),
        BinaryOp::UnsignedSaturatingAdd => {
            return Err("SPU saturating add uses compare and mask lowering".into())
        }
    };
    let immediate = match op {
        BinaryOp::LShr | BinaryOp::AShr => -immediate,
        _ => immediate,
    };
    Ok(format!(
        "{instruction} ${destination},${source},{immediate}"
    ))
}

fn immediate_value(op: BinaryOp, value: i32, constant_is_lhs: bool) -> Option<i32> {
    if matches!(op, BinaryOp::RotateLeft | BinaryOp::RotateRight) {
        return None;
    }
    if is_minmax(op) {
        return None;
    }
    if op == BinaryOp::UnsignedSaturatingAdd {
        return None;
    }
    if op == BinaryOp::Mul {
        return None;
    }
    if matches!(op, BinaryOp::Shl | BinaryOp::LShr | BinaryOp::AShr) {
        return (!constant_is_lhs && (0..=31).contains(&value)).then_some(value);
    }
    if constant_is_lhs && op == BinaryOp::Sub {
        return None;
    }
    let immediate = if op == BinaryOp::Sub {
        value.wrapping_neg()
    } else {
        value
    };
    (-512..=511).contains(&immediate).then_some(immediate)
}

fn immediate_is_encodable(op: BinaryOp, value: i32, constant_is_lhs: bool) -> bool {
    immediate_value(op, value, constant_is_lhs).is_some()
}

fn lower_constant_binary(
    op: BinaryOp,
    destination: usize,
    source: usize,
    value: i32,
    constant_is_lhs: bool,
) -> Result<Vec<String>, String> {
    let mut operations = materialize_i32(destination, value);
    let (lhs, rhs) = if constant_is_lhs {
        (destination, source)
    } else {
        (source, destination)
    };
    operations.push(lower_binary_register(op, destination, lhs, rhs)?);
    Ok(operations)
}

fn lower_binary_register(
    op: BinaryOp,
    destination: usize,
    lhs: usize,
    rhs: usize,
) -> Result<String, String> {
    Ok(match op {
        BinaryOp::Add => format!("a ${destination},${lhs},${rhs}"),
        // SPU `sf rt, ra, rb` computes rb - ra.
        BinaryOp::Sub => format!("sf ${destination},${rhs},${lhs}"),
        BinaryOp::Mul => {
            return Err("full-width SPU multiply requires a multi-instruction expansion".into())
        }
        BinaryOp::And => format!("and ${destination},${lhs},${rhs}"),
        BinaryOp::Or => format!("or ${destination},${lhs},${rhs}"),
        BinaryOp::Xor => format!("xor ${destination},${lhs},${rhs}"),
        BinaryOp::Shl => format!("shl ${destination},${lhs},${rhs}"),
        BinaryOp::RotateLeft => format!("rot ${destination},${lhs},${rhs}"),
        BinaryOp::RotateRight => {
            return Err("variable right rotations require a negated count register".into())
        }
        BinaryOp::SignedMin
        | BinaryOp::SignedMax
        | BinaryOp::UnsignedMin
        | BinaryOp::UnsignedMax => return Err("SPU min/max use compare and select lowering".into()),
        BinaryOp::UnsignedSaturatingAdd => {
            return Err("SPU saturating add uses compare and mask lowering".into())
        }
        BinaryOp::LShr | BinaryOp::AShr => {
            return Err("variable right shifts require a negated count register".into())
        }
    })
}

fn is_minmax(op: BinaryOp) -> bool {
    matches!(
        op,
        BinaryOp::SignedMin | BinaryOp::SignedMax | BinaryOp::UnsignedMin | BinaryOp::UnsignedMax
    )
}

fn lower_minmax(
    op: BinaryOp,
    destination: usize,
    lhs: usize,
    rhs: usize,
    next_temp: &mut usize,
    free_temps: &mut BTreeSet<usize>,
) -> Result<Vec<String>, String> {
    let mask = allocate_scratch(next_temp, free_temps)
        .map_err(|_| "SPU min/max needs one additional caller-saved SPU register")?;
    let compare = match op {
        BinaryOp::SignedMin | BinaryOp::SignedMax => "cgt",
        BinaryOp::UnsignedMin | BinaryOp::UnsignedMax => "clgt",
        _ => return Err("expected an SPU min/max operation".into()),
    };
    // Compare lhs > rhs. For min, select rhs when true; for max, select lhs.
    let (select_a, select_b) = if matches!(op, BinaryOp::SignedMax | BinaryOp::UnsignedMax) {
        (rhs, lhs)
    } else {
        (lhs, rhs)
    };
    let operations = vec![
        format!("{compare} ${mask},${lhs},${rhs}"),
        format!("selb ${destination},${select_a},${select_b},${mask}"),
    ];
    free_temps.insert(mask);
    Ok(operations)
}

fn lower_unsigned_saturating_add(
    destination: usize,
    lhs: usize,
    rhs: usize,
    next_temp: &mut usize,
    free_temps: &mut BTreeSet<usize>,
) -> Result<Vec<String>, String> {
    let sum = allocate_scratch(next_temp, free_temps)
        .map_err(|_| "unsigned saturating add needs one additional caller-saved SPU register")?;
    // A wrapped unsigned sum is smaller than either nonzero addend. `clgt`
    // produces an all-ones mask on overflow, so OR saturates the result to MAX.
    let operations = vec![
        format!("a ${sum},${lhs},${rhs}"),
        format!("clgt ${destination},${lhs},${sum}"),
        format!("or ${destination},${sum},${destination}"),
    ];
    free_temps.insert(sum);
    Ok(operations)
}

fn lower_multiply(
    destination: usize,
    lhs: usize,
    rhs: usize,
    next_temp: &mut usize,
    free_temps: &mut BTreeSet<usize>,
) -> Result<Vec<String>, String> {
    // The SPU multiply instructions operate on halfwords. The low 32 bits of
    // a full i32 product are the low-halfword product plus both cross products
    // shifted left by 16 bits. mpyh already returns that shifted cross product.
    let error = "full-width multiply needs two additional caller-saved SPU registers";
    let cross_lhs_rhs = allocate_scratch(next_temp, free_temps).map_err(|_| error)?;
    let cross_rhs_lhs = match allocate_scratch(next_temp, free_temps) {
        Ok(register) => register,
        Err(_) => {
            free_temps.insert(cross_lhs_rhs);
            return Err(error.into());
        }
    };
    let operations = vec![
        format!("mpyh ${cross_lhs_rhs},${lhs},${rhs}"),
        format!("mpyh ${cross_rhs_lhs},${rhs},${lhs}"),
        format!("mpyu ${destination},${lhs},${rhs}"),
        format!("a ${cross_lhs_rhs},${cross_lhs_rhs},${cross_rhs_lhs}"),
        format!("a ${destination},${destination},${cross_lhs_rhs}"),
    ];
    free_temps.insert(cross_lhs_rhs);
    free_temps.insert(cross_rhs_lhs);
    Ok(operations)
}

fn allocate_scratch(
    next_temp: &mut usize,
    free_temps: &mut BTreeSet<usize>,
) -> Result<usize, String> {
    if let Some(register) = free_temps.pop_first() {
        Ok(register)
    } else if *next_temp < 80 {
        let register = *next_temp;
        *next_temp += 1;
        Ok(register)
    } else {
        Err("no caller-saved SPU scratch register is available".into())
    }
}

fn lower_variable_shift(
    op: BinaryOp,
    destination: usize,
    source: usize,
    count: usize,
    count_is_dead: bool,
    next_temp: &mut usize,
    free_temps: &mut BTreeSet<usize>,
) -> Result<Vec<String>, String> {
    if op == BinaryOp::Shl {
        return Ok(vec![format!("shl ${destination},${source},${count}")]);
    }
    let (negated_count, scratch) = if count_is_dead && count != source {
        (count, false)
    } else if let Some(temp) = free_temps.pop_first() {
        (temp, true)
    } else if *next_temp < 80 {
        let temp = *next_temp;
        *next_temp += 1;
        (temp, true)
    } else {
        return Err("variable right shift needs an extra caller-saved SPU register".into());
    };
    let shift = match op {
        BinaryOp::LShr => "rotm",
        BinaryOp::AShr => "rotma",
        _ => return Err("expected a right-shift operation".into()),
    };
    let operations = vec![
        format!("sfi ${negated_count},${count},0"),
        format!("{shift} ${destination},${source},${negated_count}"),
    ];
    if scratch {
        free_temps.insert(negated_count);
    }
    Ok(operations)
}

fn lower_trailing_zeros(
    destination: usize,
    source: usize,
    next_temp: &mut usize,
    free_temps: &mut BTreeSet<usize>,
) -> Result<Vec<String>, String> {
    let error = "trailing_zeros needs two additional caller-saved SPU registers";
    let zero_mask = allocate_scratch(next_temp, free_temps).map_err(|_| error)?;
    let negated = match allocate_scratch(next_temp, free_temps) {
        Ok(register) => register,
        Err(_) => {
            free_temps.insert(zero_mask);
            return Err(error.into());
        }
    };
    let operations = vec![
        format!("ceqi ${zero_mask},${source},0"),
        format!("sfi ${negated},${source},0"),
        format!("and ${negated},${source},${negated}"),
        format!("clz ${destination},${negated}"),
        format!("sfi ${destination},${destination},31"),
        format!("andi ${zero_mask},${zero_mask},33"),
        format!("a ${destination},${destination},${zero_mask}"),
    ];
    free_temps.insert(zero_mask);
    free_temps.insert(negated);
    Ok(operations)
}

fn lower_wrapping_abs(
    destination: usize,
    source: usize,
    next_temp: &mut usize,
    free_temps: &mut BTreeSet<usize>,
) -> Result<Vec<String>, String> {
    let sign = allocate_scratch(next_temp, free_temps)
        .map_err(|_| "wrapping_abs needs one additional caller-saved SPU register")?;
    let operations = vec![
        format!("rotmai ${sign},${source},-31"),
        format!("xor ${destination},${source},${sign}"),
        format!("sf ${destination},${sign},${destination}"),
    ];
    free_temps.insert(sign);
    Ok(operations)
}

fn lower_rotate_immediate(op: BinaryOp, destination: usize, source: usize, count: i32) -> String {
    let count = (count as u32 & 31) as i32;
    let count = if op == BinaryOp::RotateRight {
        -count
    } else {
        count
    };
    format!("roti ${destination},${source},{count}")
}

fn lower_variable_rotate_right(
    destination: usize,
    source: usize,
    count: usize,
    count_is_dead: bool,
    next_temp: &mut usize,
    free_temps: &mut BTreeSet<usize>,
) -> Result<Vec<String>, String> {
    let (negated_count, scratch) = if count_is_dead && count != source {
        (count, false)
    } else if let Some(temp) = free_temps.pop_first() {
        (temp, true)
    } else if *next_temp < 80 {
        let temp = *next_temp;
        *next_temp += 1;
        (temp, true)
    } else {
        return Err("variable right rotation needs an extra caller-saved SPU register".into());
    };
    let operations = vec![
        format!("sfi ${negated_count},${count},0"),
        format!("rot ${destination},${source},${negated_count}"),
    ];
    if scratch {
        free_temps.insert(negated_count);
    }
    Ok(operations)
}

fn lower_compare(predicate: Predicate, destination: usize, lhs: usize, rhs: usize) -> Vec<String> {
    let (instruction, lhs, rhs, invert) = match predicate {
        Predicate::Eq => ("ceq", lhs, rhs, false),
        Predicate::Ne => ("ceq", lhs, rhs, true),
        Predicate::SignedGt => ("cgt", lhs, rhs, false),
        Predicate::SignedGe => ("cgt", rhs, lhs, true),
        Predicate::SignedLt => ("cgt", rhs, lhs, false),
        Predicate::SignedLe => ("cgt", lhs, rhs, true),
        Predicate::UnsignedGt => ("clgt", lhs, rhs, false),
        Predicate::UnsignedGe => ("clgt", rhs, lhs, true),
        Predicate::UnsignedLt => ("clgt", rhs, lhs, false),
        Predicate::UnsignedLe => ("clgt", lhs, rhs, true),
    };
    let mut operations = vec![format!("{instruction} ${destination},${lhs},${rhs}")];
    if invert {
        operations.push(format!("nor ${destination},${destination},${destination}"));
    }
    // SPU compare instructions produce an all-ones word for true. Rust's C
    // ABI bool is zero-extended, so normalize it to an integer 0 or 1.
    operations.push(format!("andi ${destination},${destination},1"));
    operations
}

fn evaluate_predicate(predicate: Predicate, lhs: i32, rhs: i32) -> bool {
    match predicate {
        Predicate::Eq => lhs == rhs,
        Predicate::Ne => lhs != rhs,
        Predicate::SignedGt => lhs > rhs,
        Predicate::SignedGe => lhs >= rhs,
        Predicate::SignedLt => lhs < rhs,
        Predicate::SignedLe => lhs <= rhs,
        Predicate::UnsignedGt => (lhs as u32) > (rhs as u32),
        Predicate::UnsignedGe => (lhs as u32) >= (rhs as u32),
        Predicate::UnsignedLt => (lhs as u32) < (rhs as u32),
        Predicate::UnsignedLe => (lhs as u32) <= (rhs as u32),
    }
}

fn materialize_i32(destination: usize, value: i32) -> Vec<String> {
    if (-32768..=32767).contains(&value) {
        return vec![format!("il ${destination},{value}")];
    }
    let bits = value as u32;
    let high = ((bits >> 16) as u16 as i16) as i32;
    let low = (bits as u16 as i16) as i32;
    vec![
        format!("ilhu ${destination},{high}"),
        format!("iohl ${destination},{low}"),
    ]
}

pub fn lower_program_to_spu_assembly(program: &Program) -> Result<String, String> {
    match program {
        Program::Scalar(function) => lower_to_spu_assembly(function),
        Program::StopEntry(name) => Ok(format!(
            ".text\n.p2align 3\n.globl {name}\n.type {name},@function\n{name}:\n  stop 0\n.size {name},.-{name}\n"
        )),
    }
}

pub fn lower_runtime_startup(function_symbol: &str, arguments: &[u32]) -> String {
    let mut setup = vec!["ilhu $1,4".to_owned(), "il $2,0".to_owned()];
    for (index, argument) in arguments.iter().enumerate() {
        let destination = index + 3;
        setup.extend(materialize_i32(destination, *argument as i32));
    }

    let mut body = String::new();
    for (index, instruction) in setup.iter().enumerate() {
        body.push_str(&format!("  {instruction}\n"));
        if index + 1 < setup.len() {
            body.push_str("  lnop\n");
        }
    }
    body.push_str(&format!("  brsl $0,{function_symbol}\n"));
    body.push_str("  wrch $ch28,$3\n  lnop\n  stop 0\n");
    format!(
        ".text\n.p2align 3\n.globl _start\n.type _start,@function\n_start:\n{body}.size _start,.-_start\n"
    )
}

impl Program {
    pub fn symbol(&self) -> &str {
        match self {
            Program::Scalar(function) => &function.name,
            Program::StopEntry(name) => name,
        }
    }

    pub fn entry_symbol(&self) -> Option<&str> {
        match self {
            Program::Scalar(_) => None,
            Program::StopEntry(name) => Some(name),
        }
    }

    pub fn runtime_entry_info(&self) -> Option<(&str, usize)> {
        match self {
            Program::Scalar(function) => Some((&function.name, function.params.len())),
            _ => None,
        }
    }
}

fn is_asm_identifier(value: &str) -> bool {
    let mut chars = value.chars();
    matches!(chars.next(), Some(c) if c.is_ascii_alphabetic() || c == '_' || c == '.' || c == '$')
        && chars.all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.' || c == '$')
}

fn is_llvm_local(value: &str) -> bool {
    value.strip_prefix('%').is_some_and(|name| {
        !name.is_empty()
            && name
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '.' || c == '$' || c == '-')
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ir(op: &str, operands: &str) -> String {
        format!(
            "define noundef i32 @f(i32 noundef %a, i32 noundef %b) unnamed_addr {{\nstart:\n  %sum = {op} i32 {operands}\n  ret i32 %sum\n}}\n"
        )
    }

    fn minmax_ir(intrinsic: &str, lhs: &str, rhs: &str) -> String {
        format!(
            "define noundef i32 @f(i32 noundef %a, i32 noundef %b) {{\nstart:\n  %result = tail call noundef i32 @llvm.{intrinsic}.i32(i32 {lhs}, i32 {rhs})\n  ret i32 %result\n}}\n"
        )
    }

    fn saturating_add_ir(lhs: &str, rhs: &str) -> String {
        format!(
            "define noundef i32 @f(i32 noundef %a, i32 noundef %b) {{\nstart:\n  %result = tail call noundef i32 @llvm.uadd.sat.i32(i32 {lhs}, i32 {rhs})\n  ret i32 %result\n}}\n"
        )
    }

    fn one_param_ir(op: &str, operands: &str) -> String {
        format!(
            "define noundef i32 @f(i32 noundef %a) unnamed_addr {{\nstart:\n  %sum = {op} i32 {operands}\n  ret i32 %sum\n}}\n"
        )
    }

    fn comparison_ir(predicate: &str) -> String {
        format!(
            "define noundef zeroext i1 @f(i32 noundef %a, i32 noundef %b) unnamed_addr {{\nstart:\n  %cmp = icmp {predicate} i32 %a, %b\n  ret i1 %cmp\n}}\n"
        )
    }

    fn rotate_ir(intrinsic: &str, count: &str) -> String {
        format!(
            "define noundef i32 @f(i32 noundef %a, i32 noundef %count) {{\nstart:\n  %rotated = tail call noundef i32 @llvm.{intrinsic}.i32(i32 %a, i32 %a, i32 {count})\n  ret i32 %rotated\n}}\n"
        )
    }

    fn leading_zeros_ir(zero_undef: &str) -> String {
        format!(
            "define noundef range(i32 0, 33) i32 @f(i32 noundef %a) {{\nstart:\n  %count = tail call noundef range(i32 0, 33) i32 @llvm.ctlz.i32(i32 %a, i1 {zero_undef})\n  ret i32 %count\n}}\n"
        )
    }

    fn trailing_zeros_ir(zero_undef: &str) -> String {
        format!(
            "define noundef range(i32 0, 33) i32 @f(i32 noundef %a) {{\nstart:\n  %count = tail call noundef range(i32 0, 33) i32 @llvm.cttz.i32(i32 %a, i1 {zero_undef})\n  ret i32 %count\n}}\n"
        )
    }

    fn count_ones_ir(value: &str) -> String {
        format!(
            "define noundef i32 @f(i32 noundef %a) {{\nstart:\n  %count = tail call noundef i32 @llvm.ctpop.i32(i32 {value})\n  ret i32 %count\n}}\n"
        )
    }

    fn wrapping_abs_ir(poison: &str) -> String {
        format!(
            "define noundef i32 @f(i32 noundef %a) {{\nstart:\n  %abs = tail call noundef i32 @llvm.abs.i32(i32 %a, i1 {poison})\n  ret i32 %abs\n}}\n"
        )
    }

    #[test]
    fn lowers_add_using_the_spu_c_abi_registers() {
        let function = parse_single_i32_binary_function(&ir("add", "%b, %a")).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  a $3,$3,$4\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn lowers_sub_in_spus_reverse_operand_order() {
        let function = parse_single_i32_binary_function(&ir("sub", "%a, %b")).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap()
            .contains("sf $3,$4,$3"));
    }

    #[test]
    fn lowers_wrapping_multiply_with_spu_halfword_products() {
        let function = parse_single_i32_binary_function(&ir("mul", "%a, %b")).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  mpyh $5,$3,$4\n  lnop\n  mpyh $6,$4,$3\n  lnop\n  mpyu $3,$3,$4\n  lnop\n  a $5,$5,$6\n  lnop\n  a $3,$3,$5\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn materializes_multiplication_constants_before_using_scratch_registers() {
        for operands in ["%a, 305419896", "305419896, %a"] {
            let function =
                parse_single_i32_binary_function(&one_param_ir("mul", operands)).unwrap();
            let assembly = lower_to_spu_assembly(&function).unwrap();
            assert!(assembly.contains("ilhu $4,4660\n  lnop\n  iohl $4,22136"));
            assert!(assembly.contains("mpyu $4,"));
            assert!(assembly.contains("or $3,$4,$4"));
        }
    }

    #[test]
    fn multiplication_uses_scratch_registers_after_all_abi_argument_registers() {
        let params = (0..72)
            .map(|index| format!("i32 %a{index}"))
            .collect::<Vec<_>>()
            .join(", ");
        let module = format!(
            "define i32 @f({params}) {{\n  %product = mul i32 %a70, %a71\n  ret i32 %product\n}}\n"
        );
        let function = parse_single_i32_binary_function(&module).unwrap();
        let assembly = lower_to_spu_assembly(&function).unwrap();
        assert!(assembly.contains("mpyh $75,$73,$74"));
        assert!(assembly.contains("mpyh $76,$74,$73"));
        assert!(assembly.contains("mpyu $3,$73,$74"));
    }

    #[test]
    fn lowers_small_add_immediate() {
        let function = parse_single_i32_binary_function(&one_param_ir("add", "%a, 1")).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap()
            .contains("ai $3,$3,1"));
    }

    #[test]
    fn lowers_subtract_constant_as_add_negative_immediate() {
        let function = parse_single_i32_binary_function(&one_param_ir("sub", "%a, 1")).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap()
            .contains("ai $3,$3,-1"));
    }

    #[test]
    fn lowers_logic_with_signed_10_bit_immediates() {
        for (op, constant, expected) in [
            ("and", "255", "andi $3,$3,255"),
            ("or", "1", "ori $3,$3,1"),
            ("xor", "1", "xori $3,$3,1"),
        ] {
            let function =
                parse_single_i32_binary_function(&one_param_ir(op, &format!("%a, {constant}")))
                    .unwrap();
            assert!(lower_to_spu_assembly(&function).unwrap().contains(expected));
        }
    }

    #[test]
    fn lowers_wrapping_shifts_with_spu_count_conventions() {
        let left = "define i32 @f(i32 %a, i32 %b) {\n  %count = and i32 %b, 31\n  %shifted = shl i32 %a, %count\n  ret i32 %shifted\n}\n";
        let right = "define i32 @f(i32 %a, i32 %b) {\n  %count = and i32 %b, 31\n  %shifted = lshr i32 %a, %count\n  ret i32 %shifted\n}\n";
        let signed_right = "define i32 @f(i32 %a, i32 %b) {\n  %count = and i32 %b, 31\n  %shifted = ashr i32 %a, %count\n  ret i32 %shifted\n}\n";
        for (module, expected) in [
            (left, "shl $3,$3,$5"),
            (right, "sfi $5,$5,0\n  lnop\n  rotm $3,$3,$5"),
            (signed_right, "sfi $5,$5,0\n  lnop\n  rotma $3,$3,$5"),
        ] {
            let function = parse_single_i32_binary_function(module).unwrap();
            let assembly = lower_to_spu_assembly(&function).unwrap();
            assert!(
                assembly.contains(expected),
                "missing {expected:?}:\n{assembly}"
            );
        }
    }

    #[test]
    fn preserves_a_shift_count_that_is_used_later() {
        let module = "define i32 @f(i32 %a, i32 %b) {\n  %shifted = lshr i32 %a, %b\n  %result = xor i32 %shifted, %b\n  ret i32 %result\n}\n";
        let function = parse_single_i32_binary_function(module).unwrap();
        let assembly = lower_to_spu_assembly(&function).unwrap();
        assert!(assembly.contains("sfi $6,$4,0\n  lnop\n  rotm $5,$3,$6"));
        assert!(assembly.contains("xor $3,$4,$5"));
    }

    #[test]
    fn uses_a_temporary_when_shift_value_and_count_are_the_same_register() {
        let module =
            "define i32 @f(i32 %a) {\n  %shifted = lshr i32 %a, %a\n  ret i32 %shifted\n}\n";
        let function = parse_single_i32_binary_function(module).unwrap();
        let assembly = lower_to_spu_assembly(&function).unwrap();
        assert!(assembly.contains("sfi $4,$3,0\n  lnop\n  rotm $3,$3,$4"));
    }

    #[test]
    fn uses_spu_immediate_right_shift_encoding() {
        for (op, expected) in [("lshr", "rotmi $3,$3,-5"), ("ashr", "rotmai $3,$3,-5")] {
            let function = parse_single_i32_binary_function(&one_param_ir(op, "%a, 5")).unwrap();
            assert!(lower_to_spu_assembly(&function).unwrap().contains(expected));
        }
    }

    #[test]
    fn lowers_rust_rotate_intrinsics_to_spu_rotate_instructions() {
        let left = parse_single_i32_binary_function(&rotate_ir("fshl", "%count")).unwrap();
        let left_assembly = lower_to_spu_assembly(&left).unwrap();
        assert!(left_assembly.contains("rot $3,$3,$4"), "{left_assembly}");

        let right = parse_single_i32_binary_function(&rotate_ir("fshr", "%count")).unwrap();
        let right_assembly = lower_to_spu_assembly(&right).unwrap();
        assert!(
            right_assembly.contains("sfi $4,$4,0\n  lnop\n  rot $3,$3,$4"),
            "{right_assembly}"
        );
    }

    #[test]
    fn right_rotation_preserves_a_live_count_and_handles_an_aliased_count() {
        let live_count = "define i32 @f(i32 %a, i32 %count) {\n  %rotated = call i32 @llvm.fshr.i32(i32 %a, i32 %a, i32 %count)\n  %result = xor i32 %rotated, %count\n  ret i32 %result\n}\n";
        let function = parse_single_i32_binary_function(live_count).unwrap();
        let assembly = lower_to_spu_assembly(&function).unwrap();
        assert!(
            assembly.contains("sfi $6,$4,0\n  lnop\n  rot $5,$3,$6\n  lnop\n  xor $3,$4,$5"),
            "{assembly}"
        );

        let aliased_count = "define i32 @f(i32 %a) {\n  %rotated = call i32 @llvm.fshr.i32(i32 %a, i32 %a, i32 %a)\n  ret i32 %rotated\n}\n";
        let function = parse_single_i32_binary_function(aliased_count).unwrap();
        let assembly = lower_to_spu_assembly(&function).unwrap();
        assert!(
            assembly.contains("sfi $4,$3,0\n  lnop\n  rot $3,$3,$4"),
            "{assembly}"
        );
    }

    #[test]
    fn lowers_rotate_intrinsics_with_constant_counts_to_roti() {
        for (intrinsic, count, expected) in [
            ("fshl", "5", "roti $3,$3,5"),
            ("fshr", "5", "roti $3,$3,-5"),
            ("fshl", "33", "roti $3,$3,1"),
            ("fshr", "33", "roti $3,$3,-1"),
        ] {
            let function = parse_single_i32_binary_function(&rotate_ir(intrinsic, count)).unwrap();
            let assembly = lower_to_spu_assembly(&function).unwrap();
            assert!(assembly.contains(expected), "{expected}:\n{assembly}");
        }
    }

    #[test]
    fn rejects_funnel_shifts_that_are_not_rotations() {
        let module = "define i32 @f(i32 %a, i32 %b, i32 %count) {\n  %x = call i32 @llvm.fshl.i32(i32 %a, i32 %b, i32 %count)\n  ret i32 %x\n}\n";
        assert!(parse_single_i32_binary_function(module)
            .unwrap_err()
            .contains("identical funnel-shift inputs"));
    }

    #[test]
    fn lowers_rust_leading_zeros_to_the_spu_clz_instruction() {
        let function = parse_single_i32_binary_function(&leading_zeros_ir("false")).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  clz $3,$3\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn rejects_undefined_zero_behavior_for_clz() {
        assert!(parse_single_i32_binary_function(&leading_zeros_ir("true"))
            .unwrap_err()
            .contains("defined-zero"));
    }

    #[test]
    fn lowers_rust_trailing_zeros_and_handles_defined_zero() {
        let function = parse_single_i32_binary_function(&trailing_zeros_ir("false")).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  ceqi $4,$3,0\n  lnop\n  sfi $5,$3,0\n  lnop\n  and $5,$3,$5\n  lnop\n  clz $3,$5\n  lnop\n  sfi $3,$3,31\n  lnop\n  andi $4,$4,33\n  lnop\n  a $3,$3,$4\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn rejects_undefined_zero_behavior_for_cttz() {
        assert!(parse_single_i32_binary_function(&trailing_zeros_ir("true"))
            .unwrap_err()
            .contains("defined-zero"));
    }

    #[test]
    fn lowers_defined_wrapping_abs_and_preserves_the_minimum_value() {
        let function = parse_single_i32_binary_function(&wrapping_abs_ir("false")).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  rotmai $4,$3,-31\n  lnop\n  xor $3,$3,$4\n  lnop\n  sf $3,$4,$3\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn rejects_poisoning_abs_at_the_signed_minimum() {
        assert!(parse_single_i32_binary_function(&wrapping_abs_ir("true"))
            .unwrap_err()
            .contains("defined-overflow"));
    }

    #[test]
    fn lowers_signed_and_unsigned_minmax_with_compare_and_select() {
        for (intrinsic, expected) in [
            ("smin", "cgt $5,$3,$4\n  lnop\n  selb $3,$3,$4,$5"),
            ("smax", "cgt $5,$3,$4\n  lnop\n  selb $3,$4,$3,$5"),
            ("umin", "clgt $5,$3,$4\n  lnop\n  selb $3,$3,$4,$5"),
            ("umax", "clgt $5,$3,$4\n  lnop\n  selb $3,$4,$3,$5"),
        ] {
            let function =
                parse_single_i32_binary_function(&minmax_ir(intrinsic, "%a", "%b")).unwrap();
            let assembly = lower_to_spu_assembly(&function).unwrap();
            assert!(assembly.contains(expected), "{intrinsic}:\n{assembly}");
        }
    }

    #[test]
    fn materializes_minmax_constants_and_folds_constant_pairs() {
        let right_constant =
            parse_single_i32_binary_function(&minmax_ir("smin", "%a", "7")).unwrap();
        let assembly = lower_to_spu_assembly(&right_constant).unwrap();
        assert!(
            assembly.contains("il $5,7\n  lnop\n  cgt $6,$3,$5"),
            "{assembly}"
        );
        assert!(assembly.contains("selb $5,$3,$5,$6"), "{assembly}");

        let left_constant =
            parse_single_i32_binary_function(&minmax_ir("umax", "305419896", "%b")).unwrap();
        let assembly = lower_to_spu_assembly(&left_constant).unwrap();
        assert!(
            assembly.contains("ilhu $5,4660\n  lnop\n  iohl $5,22136"),
            "{assembly}"
        );
        assert!(assembly.contains("clgt $6,$5,$4"), "{assembly}");

        let constants = "define i32 @f() {\n  %result = call i32 @llvm.smax.i32(i32 -4, i32 9)\n  ret i32 %result\n}\n";
        let function = parse_single_i32_binary_function(&constants).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap()
            .contains("il $3,9\n  bi $0"));
    }

    #[test]
    fn lowers_unsigned_saturating_add_and_handles_overflow() {
        let function = parse_single_i32_binary_function(&saturating_add_ir("%a", "%b")).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  a $5,$3,$4\n  lnop\n  clgt $3,$3,$5\n  lnop\n  or $3,$5,$3\n  bi $0\n.size f,.-f\n"
        );

        let constants = "define i32 @f() {\n  %result = call i32 @llvm.uadd.sat.i32(i32 4294967295, i32 1)\n  ret i32 %result\n}\n";
        let function = parse_single_i32_binary_function(constants).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap()
            .contains("il $3,-1\n  bi $0"));

        let constant_rhs = "define i32 @f(i32 noundef %a) {\n  %result = call i32 @llvm.uadd.sat.i32(i32 %a, i32 7)\n  ret i32 %result\n}\n";
        let function = parse_single_i32_binary_function(constant_rhs).unwrap();
        let assembly = lower_to_spu_assembly(&function).unwrap();
        assert!(
            assembly.contains("il $4,7\n  lnop\n  a $5,$3,$4"),
            "{assembly}"
        );
        assert!(
            assembly.contains("clgt $4,$3,$5\n  lnop\n  or $4,$5,$4"),
            "{assembly}"
        );
    }

    #[test]
    fn lowers_rust_count_ones_to_spu_bit_count_sequence() {
        let function = parse_single_i32_binary_function(&count_ones_ir("%a")).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  cntb $3,$3\n  lnop\n  sumb $3,$3,$3\n  lnop\n  xshw $3,$3\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn folds_constant_count_ones() {
        let function = parse_single_i32_binary_function(&count_ones_ir("-1")).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap()
            .contains("il $3,32\n  bi $0"));
    }

    #[test]
    fn lowers_all_signed_and_unsigned_integer_predicates_to_bool() {
        for (predicate, expected) in [
            ("eq", "ceq $3,$3,$4\n  lnop\n  andi $3,$3,1"),
            (
                "ne",
                "ceq $3,$3,$4\n  lnop\n  nor $3,$3,$3\n  lnop\n  andi $3,$3,1",
            ),
            ("sgt", "cgt $3,$3,$4\n  lnop\n  andi $3,$3,1"),
            (
                "sge",
                "cgt $3,$4,$3\n  lnop\n  nor $3,$3,$3\n  lnop\n  andi $3,$3,1",
            ),
            ("slt", "cgt $3,$4,$3\n  lnop\n  andi $3,$3,1"),
            (
                "sle",
                "cgt $3,$3,$4\n  lnop\n  nor $3,$3,$3\n  lnop\n  andi $3,$3,1",
            ),
            ("ugt", "clgt $3,$3,$4\n  lnop\n  andi $3,$3,1"),
            (
                "uge",
                "clgt $3,$4,$3\n  lnop\n  nor $3,$3,$3\n  lnop\n  andi $3,$3,1",
            ),
            ("ult", "clgt $3,$4,$3\n  lnop\n  andi $3,$3,1"),
            (
                "ule",
                "clgt $3,$3,$4\n  lnop\n  nor $3,$3,$3\n  lnop\n  andi $3,$3,1",
            ),
        ] {
            let program = parse_supported_program(&comparison_ir(predicate)).unwrap();
            let assembly = lower_program_to_spu_assembly(&program).unwrap();
            assert!(assembly.contains(expected), "{predicate}:\n{assembly}");
            assert_eq!(program.symbol(), "f");
            assert_eq!(program.entry_symbol(), None);
        }
    }

    #[test]
    fn materializes_a_comparison_constant_without_clobbering_arguments() {
        let module = "define noundef zeroext i1 @f(i32 noundef %a) {\n  %cmp = icmp eq i32 %a, 0\n  ret i1 %cmp\n}\n";
        let program = parse_supported_program(module).unwrap();
        let assembly = lower_program_to_spu_assembly(&program).unwrap();
        assert!(assembly.contains("ceq $4,$3,$4"));
        assert!(assembly.contains("or $3,$4,$4"));
        assert!(assembly.contains("andi $4,$4,1"));
    }

    #[test]
    fn materializes_a_constant_when_it_exceeds_the_immediate_range() {
        let function = parse_single_i32_binary_function(&one_param_ir("add", "%a, 1024")).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  il $4,1024\n  lnop\n  a $4,$3,$4\n  lnop\n  or $3,$4,$4\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn lowers_constant_minus_parameter_with_register_operands() {
        let function = parse_single_i32_binary_function(&one_param_ir("sub", "1, %a")).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  il $4,1\n  lnop\n  sf $4,$3,$4\n  lnop\n  or $3,$4,$4\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn materializes_subtract_negative_512_instead_of_overflowing_ai() {
        let function = parse_single_i32_binary_function(&one_param_ir("sub", "%a, -512")).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap()
            .contains("sf $4,$4,$3"));
    }

    #[test]
    fn lowers_linear_multi_operation_functions_with_temporaries() {
        let module = "define i32 @f(i32 %a, i32 %b) {\n  %x = add i32 %a, %b\n  %y = xor i32 %x, %b\n  ret i32 %y\n}\n";
        let function = parse_single_i32_binary_function(module).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  a $5,$3,$4\n  lnop\n  xor $3,$4,$5\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn returns_an_argument_through_the_abi_result_register() {
        let module = "define i32 @f(i32 %a, i32 %b) {\n  ret i32 %b\n}\n";
        let function = parse_single_i32_binary_function(module).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap()
            .contains("or $3,$4,$4"));
    }

    #[test]
    fn maps_the_seventy_second_argument_to_the_last_argument_register() {
        let params = (0..72)
            .map(|index| format!("i32 %a{index}"))
            .collect::<Vec<_>>()
            .join(", ");
        let module = format!("define i32 @f({params}) {{\n  ret i32 %a71\n}}\n");
        let function = parse_single_i32_binary_function(&module).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap()
            .contains("or $3,$74,$74"));
    }

    #[test]
    fn rejects_parameters_that_would_be_passed_on_the_stack() {
        let params = (0..73)
            .map(|index| format!("i32 %a{index}"))
            .collect::<Vec<_>>()
            .join(", ");
        let module = format!("define i32 @f({params}) {{\n  ret i32 %a72\n}}\n");
        assert!(parse_single_i32_binary_function(&module)
            .unwrap_err()
            .contains("stack"));
    }

    #[test]
    fn lowers_a_parameterless_signed_16_bit_constant_return() {
        let module = "define i32 @f() {\n  ret i32 42\n}\n";
        let function = parse_single_i32_binary_function(module).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  il $3,42\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn lowers_full_width_i32_constant_returns() {
        let module = "define i32 @f() {\n  ret i32 305419896\n}\n";
        let function = parse_single_i32_binary_function(module).unwrap();
        assert_eq!(
            lower_to_spu_assembly(&function).unwrap(),
            ".text\n.p2align 3\n.globl f\n.type f,@function\nf:\n  ilhu $3,4660\n  lnop\n  iohl $3,22136\n  bi $0\n.size f,.-f\n"
        );
    }

    #[test]
    fn reuses_temporaries_in_a_long_straight_line_chain() {
        let mut module = String::from("define i32 @f(i32 %a) {\n");
        for index in 0..100 {
            let lhs = if index == 0 {
                "%a".to_owned()
            } else {
                format!("%v{}", index - 1)
            };
            module.push_str(&format!("  %v{index} = add i32 {lhs}, 1\n"));
        }
        module.push_str("  ret i32 %v99\n}\n");
        let function = parse_single_i32_binary_function(&module).unwrap();
        let assembly = lower_to_spu_assembly(&function).unwrap();
        assert!(assembly.contains("ai $4,$5,1"));
        assert!(assembly.contains("ai $5,$4,1"));
    }

    #[test]
    fn rejects_functions_with_too_many_live_temporaries() {
        let mut module = String::from("define i32 @f(i32 %a) {\n");
        for index in 0..77 {
            module.push_str(&format!("  %v{index} = add i32 %a, 1\n"));
        }
        let mut previous = String::from("%v0");
        for index in 1..77 {
            let result = format!("%r{index}");
            module.push_str(&format!("  {result} = add i32 {previous}, %v{index}\n"));
            previous = result;
        }
        module.push_str(&format!("  ret i32 {previous}\n}}\n"));
        let function = parse_single_i32_binary_function(&module).unwrap();
        assert!(lower_to_spu_assembly(&function)
            .unwrap_err()
            .contains("more than the available caller-saved SPU registers"));
    }

    #[test]
    fn rejects_non_i32_operations() {
        let module = "define i64 @f(i64 %a, i64 %b) {\n  %x = add i64 %a, %b\n  ret i64 %x\n}\n";
        assert!(parse_single_i32_binary_function(module)
            .unwrap_err()
            .contains("returning i32"));
    }

    #[test]
    fn accepts_only_the_minimal_no_return_stop_entry() {
        let module = "define void @_start() {\nstart:\n  tail call void asm sideeffect inteldialect \"stop 0\", \"~{dirflag},~{fpsr},~{flags}\"()\n  unreachable\n}\n";
        let program = parse_supported_program(module).unwrap();
        assert_eq!(program.entry_symbol(), Some("_start"));
        assert!(lower_program_to_spu_assembly(&program)
            .unwrap()
            .contains("stop 0"));
    }

    #[test]
    fn startup_materializes_scalar_entry_arguments_in_abi_registers() {
        assert_eq!(
            lower_runtime_startup("add_u32", &[0x1234, 0x1234_5678]),
            ".text\n.p2align 3\n.globl _start\n.type _start,@function\n_start:\n  ilhu $1,4\n  lnop\n  il $2,0\n  lnop\n  il $3,4660\n  lnop\n  ilhu $4,4660\n  lnop\n  iohl $4,22136\n  brsl $0,add_u32\n  wrch $ch28,$3\n  lnop\n  stop 0\n.size _start,.-_start\n"
        );
    }

    #[test]
    fn scalar_program_reports_its_entry_argument_count() {
        let module = "define i32 @add(i32 %left, i32 %right) {\n  %sum = add i32 %left, %right\n  ret i32 %sum\n}\n";
        let program = parse_supported_program(module).unwrap();
        assert_eq!(program.runtime_entry_info(), Some(("add", 2)));
    }

    #[test]
    fn rejects_other_inline_assembly() {
        let module = "define void @_start() {\nstart:\n  call void asm sideeffect inteldialect \"nop\", \"~{dirflag},~{fpsr},~{flags}\"()\n  unreachable\n}\n";
        assert!(parse_supported_program(module)
            .unwrap_err()
            .contains("unsupported LLVM IR"));
    }

    #[test]
    fn rejects_inline_assembly_that_only_mentions_stop() {
        let module = "define void @_start() {\nstart:\n  call void asm sideeffect inteldialect \"nop; stop 0\", \"~{dirflag},~{fpsr},~{flags}\"()\n  unreachable\n}\n";
        assert!(parse_supported_program(module)
            .unwrap_err()
            .contains("unsupported LLVM IR"));
    }
}
