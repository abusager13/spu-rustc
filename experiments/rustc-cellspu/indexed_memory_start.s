.text
.p2align 3
.globl _start
.type _start,@function
_start:
  ilhu $1,3
  lnop
  iohl $1,0xffe0
  lnop

  ila $3,indexed_words
  lnop
  il $4,0
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,1
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,2
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,3
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,4
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,5
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,6
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,7
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,1
  lnop
  ilhu $5,0xdead
  lnop
  iohl $5,0xbeef
  lnop
  brsl $0,store_indexed
  lnop

  ila $3,indexed_words
  lnop
  il $4,4
  lnop
  ilhu $5,0x1234
  lnop
  iohl $5,0x5678
  lnop
  brsl $0,store_indexed
  lnop

  ila $3,indexed_words
  lnop
  il $4,7
  lnop
  ilhu $5,0x0bad
  lnop
  iohl $5,0xf00d
  lnop
  brsl $0,store_indexed
  lnop

  ila $3,indexed_words
  lnop
  il $4,0
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,1
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,2
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,3
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,4
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,5
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,6
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  ila $3,indexed_words
  lnop
  il $4,7
  lnop
  brsl $0,load_indexed
  lnop
  wrch $ch28,$3
  lnop

  stop 0
.size _start,.-_start

.data
.p2align 4
indexed_words:
  .long 0x11111111
  .long 0x22222222
  .long 0x33333333
  .long 0x44444444
  .long 0x55555555
  .long 0x66666666
  .long 0x77777777
  .long 0x88888888
