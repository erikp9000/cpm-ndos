===========================================================
Build NDOS and tools:

  submit make.sub
  
  MAC and RMAC assume drive P is the Line Printer. If you
  do not suppress the PRN and SYM files when building on
  drive P, then MAC/RMAC will try to send them to the line
  printer and freeze.
  
===========================================================
Build Relocatable Command Console Processor (CCP):

  asm ccpr
  ddt ccpr.hex
  -iccp20.bin
  -r400
  -^C
  save 12 ccp.com

===========================================================
