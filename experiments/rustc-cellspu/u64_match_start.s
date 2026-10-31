.text
.p2align 3
.globl _start
.type _start,@function

.macro check_match function
  brsl $0,\function
  wrch $ch28,$3
.endm

_start:
  ilhu $1,3
  iohl $1,0xffe0
  check_match match64_zero
  check_match match64_one_high
  check_match match64_sixteen_high
  check_match match64_ff_high
  check_match match64_max
  check_match match64_mixed
  check_match match64_low_signed_max
  check_match match64_low_sign_bit
  check_match match64_low_max
  check_match match64_one_high_plus_one
  check_match match64_sign_bit
  stop 0
.size _start,.-_start
