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
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  il $3,7
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  il $3,6
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  il $3,20
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  il $3,100
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  il $3,1000
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  il $3,4096
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  ilhu $3,-1
  lnop
  iohl $3,65534
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  il $3,99
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  il $3,101
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  il $3,4095
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  ilhu $3,-1
  lnop
  iohl $3,-1
  lnop
  brsl $0,classify_sparse
  lnop
  wrch $ch28,$3
  lnop

  stop 0
.size _start,.-_start
