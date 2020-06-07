===========================================================
Build NDOS and tools:

  submit make.sub
  
===========================================================
Build Relocatable Command Console Processor (CCP):

  asm ccpr
  ddt ccpr.hex
  -i ccp20.bin
  -r400
  -^C
  save 12 ccp.com

===========================================================
