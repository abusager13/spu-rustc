.text
.p2align 3
.globl _start
.type _start,@function

.macro call_u16_2 fn, arg1, arg2
  il $3, \arg1
  lnop
  il $4, \arg2
  lnop
  brsl $0, \fn
  lnop
  ila $2, 0xffff
  lnop
  and $3, $3, $2
  lnop
  wrch $ch28, $3
  lnop
.endm

.macro call_u16_1 fn, arg1
  il $3, \arg1
  lnop
  brsl $0, \fn
  lnop
  ila $2, 0xffff
  lnop
  and $3, $3, $2
  lnop
  wrch $ch28, $3
  lnop
.endm

.macro call_i16_2 fn, arg1, arg2
  il $3, \arg1
  lnop
  il $4, \arg2
  lnop
  brsl $0, \fn
  lnop
  xshw $3, $3
  lnop
  wrch $ch28, $3
  lnop
.endm

.macro call_i16_1 fn, arg1
  il $3, \arg1
  lnop
  brsl $0, \fn
  lnop
  xshw $3, $3
  lnop
  wrch $ch28, $3
  lnop
.endm

.macro call_u8_2 fn, arg1, arg2
  il $3, \arg1
  lnop
  il $4, \arg2
  lnop
  brsl $0, \fn
  lnop
  andi $3, $3, 0xff
  lnop
  wrch $ch28, $3
  lnop
.endm

_start:
  ilhu $1, 3
  lnop
  iohl $1, 0xffe0
  lnop

  # 1. add_u16(1000, 2345) -> 3345 (0x0d11)
  call_u16_2 add_u16, 1000, 2345

  # 2. add_u16_imm(1000) -> 1042 (0x0412)
  call_u16_1 add_u16_imm, 1000

  # 3. sub_u16(3345, 1000) -> 2345 (0x0929)
  call_u16_2 sub_u16, 3345, 1000

  # 4. sub_u16_imm(1042) -> 1000 (0x03e8)
  call_u16_1 sub_u16_imm, 1042

  # 5. mul_u16(123, 45) -> 5535 (0x159f)
  call_u16_2 mul_u16, 123, 45

  # 6. mul_u16_imm(123) -> 1230 (0x04ce)
  call_u16_1 mul_u16_imm, 123

  # 7. and_u16(0x1234, 0x0ff0) -> 0x0230
  call_u16_2 and_u16, 0x1234, 0x0ff0

  # 8. or_u16(0x1204, 0x0030) -> 0x1234
  call_u16_2 or_u16, 0x1204, 0x0030

  # 9. xor_u16(0x1234, 0x0ff0) -> 0x1dc4
  call_u16_2 xor_u16, 0x1234, 0x0ff0

  # 10. shl_u16(0x0123, 4) -> 0x1230
  call_u16_2 shl_u16, 0x0123, 4

  # 11. shl_u16_imm(0x0123) -> 0x2460 (shifted by 5)
  call_u16_1 shl_u16_imm, 0x0123

  # 12. shr_u16(0x1230, 4) -> 0x0123
  call_u16_2 shr_u16, 0x1230, 4

  # 13. shr_u16_imm(0x2460) -> 0x0123 (shifted by 5)
  call_u16_1 shr_u16_imm, 0x2460

  # 14. ashr_i16(-160, 4) -> -10 (0xfffffff6)
  call_i16_2 ashr_i16, -160, 4

  # 15. ashr_i16_imm(-320) -> -10 (0xfffffff6, shifted by 5)
  call_i16_1 ashr_i16_imm, -320

  # 16. add_u8(100, 42) -> 142 (0x008e)
  call_u8_2 add_u8, 100, 42

  # 17. sub_u8(142, 42) -> 100 (0x0064)
  call_u8_2 sub_u8, 142, 42

  # 18. mul_u8(12, 10) -> 120 (0x0078)
  call_u8_2 mul_u8, 12, 10

  # 19. and_u8(0xf3, 0x0f) -> 0x03
  call_u8_2 and_u8, 0xf3, 0x0f

  # 20. or_u8(0xf0, 0x0f) -> 0xff
  call_u8_2 or_u8, 0xf0, 0x0f

  # 21. xor_u8(0xff, 0x55) -> 0xaa
  call_u8_2 xor_u8, 0xff, 0x55

  # 22. sign_extend_i8_to_i32(-5) -> -5 (0xfffffffb)
  il $3, -5
  lnop
  brsl $0, sign_extend_i8_to_i32
  lnop
  wrch $ch28, $3
  lnop

  # 23. zero_extend_u8_to_u32(0xfe) -> 0x000000fe
  il $3, 0xfe
  lnop
  brsl $0, zero_extend_u8_to_u32
  lnop
  wrch $ch28, $3
  lnop

  # 24. sign_extend_i16_to_i32(-1000) -> -1000 (0xfffffc18)
  il $3, -1000
  lnop
  brsl $0, sign_extend_i16_to_i32
  lnop
  wrch $ch28, $3
  lnop

  # 25. zero_extend_u16_to_u32(0xbeef) -> 0x0000beef
  ila $3, 0xbeef
  lnop
  brsl $0, zero_extend_u16_to_u32
  lnop
  wrch $ch28, $3
  lnop

  # 26. mul_u16_widening(1000, 2000) -> 2000000 (0x001e8480)
  il $3, 1000
  lnop
  il $4, 2000
  lnop
  brsl $0, mul_u16_widening
  lnop
  wrch $ch28, $3
  lnop

  stop 0
.size _start,.-_start
