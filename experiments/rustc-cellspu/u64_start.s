.text
.p2align 3
.globl _start
.type _start,@function
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
  stop 0
.size _start,.-_start
