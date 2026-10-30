.text
.p2align 3
.globl _start
.type _start,@function
_start:
  ilhu $1,4
  lnop
  il $3,20
  lnop
  il $4,22
  lnop
  brsl $0,add_u32
  lnop
  wrch $ch28,$3
  lnop
  stop 0
.size _start,.-_start
