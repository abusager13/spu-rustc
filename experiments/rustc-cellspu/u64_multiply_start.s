.text
.p2align 3
.globl _start
.type _start,@function
_start:
  ilhu $1,3
  lnop
  iohl $1,0xffe0
  lnop
  brsl $0,product_0_high
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,product_0_low
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,product_1_high
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,product_1_low
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,product_2_high
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,product_2_low
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,product_3_high
  lnop
  wrch $ch28,$3
  lnop
  brsl $0,product_3_low
  lnop
  wrch $ch28,$3
  lnop
  stop 0
.size _start,.-_start
