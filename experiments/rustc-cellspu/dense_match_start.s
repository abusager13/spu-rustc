.text
.p2align 3
.globl _start
.type _start,@function
_start:
  ilhu $1,3
  lnop
  iohl $1,0xffe0
  lnop
  il $3,0
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,1
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,2
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,3
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,4
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,5
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,6
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,7
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,8
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,9
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,10
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  il $3,-1
  lnop
  brsl $0,classify
  lnop
  wrch $ch28,$3
  lnop
  stop 0
.size _start,.-_start
