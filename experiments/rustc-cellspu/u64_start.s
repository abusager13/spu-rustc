.text
.p2align 3
.globl _start
.type _start,@function
.macro shift_pair hihi,hilo,lohi,lolo,amount,highfn,lowfn
  ilhu $6,\hihi
  lnop
  iohl $6,\hilo
  lnop
  ilhu $5,\lohi
  lnop
  iohl $5,\lolo
  lnop
  lqa $3,.Lshift_mask
  lnop
  shufb $3,$6,$5,$3
  lnop
  il $4,\amount
  lnop
  brsl $0,\highfn
  lnop
  wrch $ch28,$3
  lnop
  ilhu $6,\hihi
  lnop
  iohl $6,\hilo
  lnop
  ilhu $5,\lohi
  lnop
  iohl $5,\lolo
  lnop
  lqa $3,.Lshift_mask
  lnop
  shufb $3,$6,$5,$3
  lnop
  il $4,\amount
  lnop
  brsl $0,\lowfn
  lnop
  wrch $ch28,$3
  lnop
.endm
_start:
  ilhu $1,3
  lnop
  iohl $1,0xffe0
  lnop
  il $3,-1
  lnop
  il $4,1
  lnop
  brsl $0,carry_word
  lnop
  wrch $ch28,$3
  lnop
  ilhu $3,0x1234
  lnop
  iohl $3,0x5678
  lnop
  ilhu $4,0x1234
  lnop
  iohl $4,0x5678
  lnop
  brsl $0,carry_word
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,high_word_sum
  lnop
  wrch $ch28,$3
  lnop
  il $3,0
  lnop
  il $4,1
  lnop
  brsl $0,borrow_word
  lnop
  wrch $ch28,$3
  lnop
  il $3,100
  lnop
  il $4,1
  lnop
  brsl $0,borrow_word
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,high_word_difference
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,high_word_and
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,low_word_and
  lnop
  wrch $ch28,$3
  lnop
  il $3,0
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,0
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  il $3,1
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,1
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  il $3,7
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,7
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  il $3,8
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,8
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  il $3,31
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,31
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  il $3,32
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,32
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  il $3,40
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,40
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  il $3,63
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,63
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  il $3,64
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,64
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  il $3,65
  lnop
  brsl $0,shift_high
  lnop
  wrch $ch28,$3
  lnop
  il $3,65
  lnop
  brsl $0,shift_low
  lnop
  wrch $ch28,$3
  lnop
  shift_pair 0x0123,0x4567,0x89ab,0xcdef,4,shift_high_value,shift_low_value
  shift_pair 0x0123,0x4567,0x89ab,0xcdef,36,shift_high_value,shift_low_value
  shift_pair 0xfedc,0xba98,0x7654,0x3210,13,shift_high_value,shift_low_value
  shift_pair 0xfedc,0xba98,0x7654,0x3210,63,shift_high_value,shift_low_value
  shift_pair 0x0123,0x4567,0x89ab,0xcdef,13,shift_high_by_13,shift_low_by_13
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,0,shift_right_high,shift_right_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,1,shift_right_high,shift_right_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,7,shift_right_high,shift_right_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,8,shift_right_high,shift_right_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,31,shift_right_high,shift_right_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,32,shift_right_high,shift_right_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,40,shift_right_high,shift_right_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,63,shift_right_high,shift_right_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,64,shift_right_high,shift_right_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,65,shift_right_high,shift_right_low
  shift_pair 0x0123,0x4567,0x89ab,0xcdef,4,shift_right_high,shift_right_low
  shift_pair 0xfedc,0xba98,0x7654,0x3210,13,shift_right_high,shift_right_low
  shift_pair 0x0123,0x4567,0x89ab,0xcdef,13,shift_right_high_by_13,shift_right_low_by_13
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,0,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,1,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,7,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,8,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,31,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,32,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,40,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,63,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,64,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,65,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x0123,0x4567,0x89ab,0xcdef,13,shift_arithmetic_high,shift_arithmetic_low
  shift_pair 0x8123,0x4567,0x89ab,0xcdef,13,shift_arithmetic_high_by_13,shift_arithmetic_low_by_13
  brsl $0,high_word_or
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,low_word_or
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,high_word_xor
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,low_word_xor
  lnop
  wrch $ch28,$3
  stop 0
.size _start,.-_start

.section .rodata,"a",@progbits
.p2align 4
.Lshift_mask:
  .long 0x00010203
  .long 0x14151617
  .long 0x08090a0b
  .long 0x1c1d1e1f
