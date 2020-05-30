;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NDOS.ASM
;; 
;; Load BDOS entry address from BDOS vector at address 6
;; Relocate ourself to BDOS vector minus 0800h (2KB)
;; Jump to the NDOS entry point
;;
;; NDOS requires a relocatable CCP.COM on drive A.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

memSz	equ 63		; kilobytes [set as appropriate]
biosSz	equ 7		; pages [set as appropriate]
bdosSz	equ 0eh		; pages, CPM 2.2 fixed
ccpSz	equ 8		; pages, CPM 2.2 fixed [but we don't care]
ndosSz	equ 8		; pages

biosBas	equ 1024*memSz - 256*biosSz
bdosBas	equ 1024*memSz - 256*(biosSz + bdosSz)
ndosBas	equ 1024*memSz - 256*(biosSz + bdosSz + ndosSz)

warmv	equ 0000h
cdisk	equ 0004h
bdosv	equ 0005h
deffcb	equ 005ch
defdma	equ 0080h
tpa	equ 0100h

image	equ 0200h	; address in TPA where the NDOS image starts
offset	equ ndosBas-image

cr	equ 0dh
lf	equ 0ah

;; Some standard BDOS functions we use
prnstr	equ 9
rstdsk	equ 0dh
openf	equ 0fh
closef	equ 10h
readf	equ 14h
setdma	equ 1ah

;; The NDOS function code extensions to NDOS
ngetver	equ 40h		; returns NDOS version as major.minor, packed BCD in A
sendmsg	equ 41h		; sends packet referenced by DE
recvmsg	equ 42h		; returns recvd packet in DE, A=0(success)/FF(timeout)
stats	equ 43h		; return HL pointing to NDOS packet counters

;; Altair 2SIO Serial port
SIOCTRL	equ 12h		; control register (write only)
  BAUD0	equ 001h	;   0=/1, 1=/16, 2=/64, 3=reset
  BAUD1	equ 002h	; 
  PAR	equ 004h	;   parity (even/odd)
  STOP	equ 008h	;   stop bits (2/1)
  BITS	equ 010h	;   data bits (7/8)
  RTS0	equ 020h	;
  RTS1	equ 040h	;
  INTE	equ 080h	;
SIOSTAT	equ 12h		; status register (read only)
  RDRF	equ 001h	;   receive data available
  TDRE	equ 002h	;   transmit buffer empty
  DCD	equ 004h	;   -Data carrier detect
  CTS	equ 008h	;   -Clear to send
  FE	equ 010h	;   framing error
  OVRN	equ 020h	;   receiver overrun
  PE	equ 040h	;   parity error
  IRQ	equ 080h	;   interrupt request
SIODATA	equ 13h		; data register (read/write)

; Receive byte timeout counter
RECVTMO	equ 32768

NDOSVER equ 10h		; packed binary coded decimal
NDOSDSK	equ 15		; drive P is the network drive

; NDOS message format:  |LEN|CMD|DATA ...|CHK|
NFNDFST	equ 02h		; DATA is |FCBlo|FCBhi|NAMEx8|EXTx3|
NFNDNXT	equ 04h		; DATA is |FCBlo|FCBhi|
NOPENF	equ 06h		; DATA is |FCBlo|FCBhi|NAMEx8|EXTx3|
NCLOSEF	equ 08h		; DATA is |FCBlo|FCBhi|
NDELETF	equ 0Ah		; DATA is |FCBlo|FCBhi|NAMEx8|EXTx3|
NREADF	equ 0Ch		; DATA is |FCBlo|FCBhi|Reclo|Rechi|
NWRITEF	equ 0Eh		; DATA is |FCBlo|FCBhi|Reclo|Rechi|Datax128|
NCREATF	equ 10h		; DATA is |FCBlo|FCBhi|NAMEx8|EXTx3|
NRENAMF	equ 12h		; DATA is |NAMEx8|EXTx3|NAMEx8|EXTx3|
NCHDIR	equ 20h		; DATA is |Path|
NMKDIR	equ 22h		; DATA is |Path|
NRMDIR	equ 24h		; DATA is |Path|
NECHO	equ 40h		; DATA is |...|

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Image relocator
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	org tpa

	; calculate version
	mvi a,NDOSVER SHR 4
	adi '0'
	sta version
	mvi a,NDOSVER AND 15
	adi '0'
	sta version+2
	mvi c,prnstr
	lxi d,signon
	call bdosv

	mvi c,ngetver
	call bdosv
	ora a
	jz install	; BDOS returns 0 when NDOS is not loaded
	
	mvi c,prnstr
	lxi d,error
	jmp bdosv	; quit
		
install:	
	lxi h,image	; source NDOS wedge
	lxi d,ndosBas	; destination
	lxi b,lastaddr-firstaddr
relocloop:
	mov a,m		; get byte at hl
	stax d		; store to de
	inx h
	inx d
	dcx b
	mov a,b
	ora c
	jnz relocloop

	;
	; Hook into BDOS jump vector
	lhld bdosv+1	; get BDOS entry address
	shld bdosadr+1	; save original BDOS entry locally
	lxi h,ndosent	; get NDOS entry address
	shld bdosv+1	; update BDOS vector so we are protected

	;
	; Hook into BIOS warm start vector
	lhld warmv+1	; get BIOS warm start
	inx h		; skip JMP byte
	mov a,m		; low-byte of warm start function
	sta warmst+1
	mvi a,ndoswarm AND 255
	mov m,a		; update BIOS jump table
	inx h
	mov a,m		; high-byte
	sta warmst+2
	mvi a,ndoswarm SHR 8
	mov m,a		; update BIOS jump table

	jmp ndoswarm	; load & execute CCP.COM

signon:	db 'NDOS '
version: db 'x.y',cr,lf
	db 'Copyright (c) 2019 Erik Petersen',cr,lf
	db '$'

error:	db 'Already running',cr,lf
	db '$'


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Resident Network DOS image starts here
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	org image

firstaddr equ $+offset

	; This makes CCP.COM happy
	db 0,22,0,0,0,0	; serial number 

ndosent	equ $+offset
	jmp ndosbeg	; standard entry point
	
fcb	equ $+offset
	db 1,'CCP     COM',0,0,0,0
	db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db 0 ; cr

noccpmsg equ $+offset
	db 'CCP.COM not found',cr,lf
	db '$'

filed	equ $+offset
	db 'CCP.COM loaded',cr,lf
	db '$'

panicmsg equ $+offset
	db cr,lf,cr,lf,'**** NDOS panic '
panicarg equ $+offset
	db 'XX ****',cr,lf
	db '$'

bdosadr	equ $+offset
	jmp 0		; jump to BDOS

warmst	equ $+offset
	jmp 0		; jump to BIOS Warm Start

functbl equ $+offset
	; BDOS function table
	;        0       1       2       3       4       5       6       7
	dw  gobdos, gobdos, gobdos, gobdos, gobdos, gobdos, gobdos, gobdos
	;        8       9      10      11      12      13      14      15
	dw  gobdos, gobdos, gobdos, gobdos, gobdos,rstdskv,seldskv, openfv
	;       16      17      18      19      20      21      22      23
	dw closefv, srchfv, srchnv,deletfv, readfv,writefv,creatfv,renamfv
	;       24      25      26      27      28      29      30      31
	dw  gobdos,getdskv,setdmav, allocv, gobdos, gobdos,setatrv,dskprmv
	;       32      33      34      35      36      37      38      39
	dw  gobdos, readrv,writerv, getszv, setrrv, gobdos, gobdos, gobdos
	;       40
	dw  wrtrfv
functblend equ $+offset

nfuncs	equ (functblend-functbl)/2

;
; Fake disk parameter block 
;
dpb	equ $+offset
	dw 0		; SPT sectors per track
	db 3		; BSH allocation block shift factor
	db 7		; BLM allocation block mask
	db 0		; EXM extent mask
	dw 15		; DSM drive storage capacity
	dw 511		; DRM directory entries
	db 0ffh,0ffh	; AL0,AL1 directory reserved blocks
	dw 0		; CHK size of directory checksum vector
	dw 0		; OFF reserved tracks

;
; Fake allocation vector - represents 16KB which is the "size" of our
; directory. Anyone who looks will conclude that the drive is full but
; we don't have to reserve memory for a meaningless allocation vector.
;
alvs	equ $+offset
	db 0ffh,0ffh
	; In the eventuality that an app requires drive space to run
	; the two bytes above plus the following are needed fo DSM = 242.
	;db     0,0,0,0,0,0, 0,0,0,0,0,0,0,0
	;db 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
	;db 0

sbuf	equ $+offset
	ds 140		; network send buffer

rbuf	equ $+offset
	ds 140		; network receive buffer

active	equ $+offset
	db 0		; current default drive

params	equ $+offset
	dw 0		; de input parameter

dmaaddr	equ $+offset
	dw 0		; the DMA address

savefcb	equ $+offset
	dw 0		; FCB address for Search for next

fndactive equ $+offset
	db 0ffh		; flag for Search for next

fndextent equ $+offset
	db 0		; Search file extent flag

retry	equ $+offset
	db 0		; message retry counter

status	equ $+offset
	dw 0		; return code

userstk	equ $+offset
	dw 0		; storage for user stack pointer

; The following block of counters is returned by
; NDOS call to stats
sentcnt	equ $+offset
	dw 0		; count of messages sent
recvcnt	equ $+offset
	dw 0		; count of messages received
tocnt	equ $+offset
	dw 0		; count of timed-out messages
chkcnt	equ $+offset
	dw 0		; count of messages with bad checksum

	ds 16
stack	equ $+offset	; NDOS stack


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NDOS warm start entry point
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ndoswarm equ $+offset

	lxi sp,stack	; set stack pointer

	mvi a,0c3h	; JMP opcode
	sta warmv
	sta bdosv
	lxi h,ndosent	; get NDOS entry address
	shld bdosv+1	; update BDOS vector so we are protected
	lxi h,biosBas+3
	shld warmv+1

	;
	; Load CCP.COM from default drive
	;
	mvi a,76h	; opcode for HLT
	sta tpa		; store HLT in TPA in case load fails
	xra a
	sta fcb+32	; cr=0
	mvi c,openf
	lxi d,fcb
	call bdosadr
	inr a
	jz noccp
	lxi d,tpa
loadloop equ $+offset
	push d		; store tpa address
	mvi c,setdma
	call bdosadr
	mvi c,readf
	lxi d,fcb
	call bdosadr
	pop h		; recover tpa address
	ora a
	jnz done
	lxi d,128
	dad d		; advance to next block in tpa
	xchg		; swap hl and de
	jmp loadloop

done	equ $+offset
	mvi c,closef
	lxi d,fcb
	call bdosadr
	mvi c,prnstr
	lxi d,filed
	call bdosadr

	lxi d,defdma
	mvi c,setdma
	call bdosadr

	lxi sp,tpa	; set stack pointer

	;
	; Copy six serial number bytes from BDOS
	; Some programs overwrite the serial number which causes CCP.COM to HALT
	; when trying to load a transient program
	mvi c,6
	lxi h,bdosBas
	lxi d,ndosBas
serloop	equ $+offset
	mov a,m
	stax d
	inx h
	inx d
	dcr c
	jnz serloop

	jmp tpa		; start CCP

noccp	equ $+offset
	mvi c,prnstr
	lxi d,noccpmsg
	call bdosadr
;	hlt
	; Restore BIOS warmst vector and call it
	lhld warmv+1	; get BIOS warm start
	inx h		; skip JMP byte
	lda warmst+1	; get old BIOS warm start
	mov m,a		; update BIOS jump table
	inx h
	lda warmst+2
	mov m,a		; update BIOS jump table	
	rst 0		; warm start!
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; BDOS/NDOS entry point
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

ndosbeg	equ $+offset
	xchg		; swap de into hl
	shld params	; save input params
	xchg		; swap de back

	lxi h,0		; 0=success
	shld status
	dad sp		; get user stack pointer
	shld userstk	; save user stack pointer
	lxi sp,stack	; change to NDOS internal stack

	; perform an indirect call by pushing 'return' onto the stack
	lxi h,return
	push h

	mov a,c		; check function code for NDOS functions
	cpi ngetver
	jz retver
	cpi sendmsg
	jz smsg
	cpi recvmsg
	jz rmsg
	cpi stats
	jz retstats

	cpi nfuncs
	jnc gobdos	; unrecognized function code, goto BDOS

	lxi h,functbl	; function table
	mov e,a		; copy function code to e
	mvi d,0
	dad d
	dad d		; hl = hl + (2 * (function code))
	mov e,m
	inx h
	mov d,m		; de = function jump vector
	lhld params	; restore input params
	xchg		; de=params, hl=jump address
	pchl		; jump to indexed function

	;
	; Return status to caller
	;
return	equ $+offset
	lhld userstk	; recover user stack pointer into hl
	sphl		; set sp from hl
	lhld status
	mov b,h
	mov a,l
	ret


	;
	; We don't handle the function, send it to BDOS
	;
gobdos	equ $+offset
;	pop h		; pop 'return' from stack
	lhld userstk	; recover user stack pointer into hl
	sphl		; set sp from hl
	jmp bdosadr


	;
	; Return NDOS version
	;
	; Inputs:
	;     None
	; Outputs:
	;     a = 10h (1.0)
	;
retver	equ $+offset
	mvi a,NDOSVER
	sta status
	ret


	;
	; Return pointer to packet stats
	;
	; Inputs:
	;     None
	; Outputs:
	;     hl = pointer
	;
retstats equ $+offset
	lxi h,sentcnt
	shld status
	ret


	;
	; Send message
	;
	; Inputs:
	;     de = pointer to buffer: |LEN|DATA ...|CHK|
	;          where LEN includes LEN and CHK bytes
	;          and CHK=0. This function will compute
	;          CHK and update the buffer.
	;          LEN = 2 + count of DATA bytes
	; Outputs:
	;     a = 0(success)/FF(failure)
	;
smsg	equ $+offset
	xchg		; get buffer pointer into hl
	in SIODATA	; reset RDRF
	mvi b,0		; init message checksum
	mov c,m		; message length
smsg1	equ $+offset
    	in SIOSTAT
	ani TDRE
	jz smsg1	; wait for transmit buffer empty

	mov a,m		; get byte to send
	out SIODATA	; send it
	add b		; add it to checksum
	mov b,a		; store in checksum register

;	nop
;	nop
;	nop
;	nop
;	nop
;	nop
;	nop
;	nop

	inx h		; advance buffer pointer
	dcr c		; decrement counter
	jz smsg2
	mov a,c
	cpi 1
	jnz smsg1	; send next byte

	; when counter hits 1, compute checksum and send it
	mov a,b		; get checksum
	cma		; a= not a
	inr a		; compute 2's complement
	mov m,a		; write to buffer
	jmp smsg1	; send it

smsg2	equ $+offset
	lhld sentcnt
	inx h
	shld sentcnt
	ret		; success


	;
	; Receive message
	;
	; Inputs:
	;     de = pointer to 256-byte buffer
	; Outputs:
	;     a = 0(success)/FF(failure)
	;     buffer will contain message: |LEN|DATA ...|CHK|
	;          LEN = 2 + count of DATA bytes
	;
rmsg	equ $+offset
	xchg		; get buffer pointer into hl
	call recvbyte
	jc rmsgto	; timeout

        mvi b,0         ; init checksum
	mov c,a         ; first byte is length

nextbyte equ $+offset
	mov m,a         ; store byte received into buffer
	inx h           ; advance buffer pointer
	add b           ; a = a + b
	mov b,a         ; b = a 
	dcr c
	jz recvchk	; check the checksum

	call recvbyte
	jnc nextbyte

rmsgto	equ $+offset
	lhld tocnt
	inx h
	shld tocnt
	mvi a,0ffh	; timeout
	sta status
	ret

recvchk	equ $+offset
	ora a		; update proc flags on a register
	jnz recvbad

	lhld recvcnt	; checksum is valid
	inx h
	shld recvcnt
	ret

recvbad	equ $+offset
	lhld chkcnt
	inx h
	shld chkcnt
	mvi a,0ffh	; bad checksum
	sta status
	ret


; carry flag is set on timeout
recvbyte equ $+offset
	lxi d,RECVTMO

recvwait equ $+offset
	in SIOSTAT
	ani RDRF
	jnz readbyte
	dcx d
	mov a,d
	ora e
	jnz recvwait
	stc		; timeout
	ret

readbyte equ $+offset
	in SIODATA
	clc		; received byte in a
	ret


	;
	; Set DMA address
	;
	; Inputs:
	;     de = DMA address
	; Outputs:
	;     None
	;
setdmav	equ $+offset
	xchg
	shld dmaaddr
	xchg
	jmp  gobdos	; send DMA address to BDOS too


	;
	; Reset disk system - sets DMA to default address
	;
	; Inputs:
	;     None
	; Outputs:
	;     None
	;
rstdskv	equ $+offset
	lxi h,defdma
	shld dmaaddr
	xra a
	sta active
	jmp  gobdos	; let BDOS handle the local disks


	;
	; Select default drive
	;
	; Inputs:
	;     e = default disk
	; Outputs:
	;     None
	;
seldskv	equ $+offset
	mov a,e
	sta active	; remember the currently active drive
	cpi NDOSDSK	; is it our disk #?
	jnz  gobdos	; unknown drive, let bdos handle it
	ret		; it's the network drive


	;
	; Get default drive
	;
	; Inputs:
	;     None
	; Outputs:
	;     a = default disk
	;
getdskv	equ $+offset
	lda active
	cpi NDOSDSK	; is it our disk #?
	jnz  gobdos	; unknown drive, let bdos handle it
	sta status
	ret		; it's the network drive


	;
	; Get disk parameter block for default drive
	;
	; Inputs:
	;     None
	; Outputs:
	;     hl = address of disk param block for current drive
	;
dskprmv	equ $+offset
	lda active
	cpi NDOSDSK	; is it our disk #?
	jnz  gobdos	; unknown drive, let bdos handle it
	lxi h,dpb
	shld status
	ret


	;
	; Get allocation for default drive
	;
	; Inputs:
	;     None
	; Outputs:
	;     hl = address of allocation vector for current drive
	;
allocv	equ $+offset
	lda active
	cpi NDOSDSK	; is it our disk #?
	jnz  gobdos	; unknown drive, let bdos handle it
	lxi h,alvs
	shld status
	ret


; internal subroutine to check if FCB at de is selecting the network disk
isnetdsk equ $+offset
	ldax d		; get drive select from FCB
	ora a		; is default drive & current user selected?
	jz checkactive
	cpi '?'		; is default drive & all users selected?
	jz checkactive
	dcr a		; convert 1-16 to 0-15
	jmp checkdisk
checkactive equ $+offset
	lda active	; get selected disk #
checkdisk equ $+offset
	cpi NDOSDSK
	rz		; the network disk is selected, return
	pop h		; remove return address from stack
	jmp  gobdos	; goto BDOS


; internal subroutine to copy filename from FCB at de into sbuf+4
getfilename equ $+offset
	lhld params	; hl = FCB address
	lxi d,sbuf+4	; destination
getfn1	equ $+offset
	mvi c,11	; filename & extension
	; ignoring bytes dr (byte 0 of FCB) and ex (byte 12)
getfn2	equ $+offset
	inx h
	mov a,m		; get byte from FCB
	stax d		; write byte to sbuf
	inx d
	dcr c
	jnz getfn2
	ret

; internal subroutine to copy filename from rbuf+5 into DMA
copynamedma equ $+offset
	lhld dmaaddr
	xchg		; de is destination
	xra a
	stax d		; set user code to 0
	lxi h,rbuf+5	; hl is source
	mvi c,15	; get filename, extension, ex, s1, s2, & rc
cpyfn1	equ $+offset
	inx d
	mov a,m		; get byte from rbuf
	stax d		; write to DMA
	inx h
	dcr c
	jnz cpyfn1
	; Fill the FCB allocation vector assuming that a block is 1024 bytes
	; and that we are using 8-bit block numbers (DSM < 256).
	; This enables STAT.COM to show the file size.
	;  a contains rc
	;  de points to alloc vector-1
	ora a
	mvi c,0		; no blocks allocated
	mvi b,16	; all blocks free
	jz cpyfn2
	mvi c,16	; all blocks allocated
	mvi b,0		; no blocks free
	jm cpyfn2
	; compute # of allocated and free blocks
	rrc
	rrc
	rrc
	ani 15		; clear msb
	inr a		; add 1
	mov c,a		; c is # allocated blocks
	mvi a,16
	sub c		; a = 16 - c
	mov b,a		; b is # free blocks
cpyfn2	equ $+offset
	mov a,c
	ora a
	jz cpyfn4
	mvi a,3		; use a non-zero block #
cpyfn3	equ $+offset
	inx d
	stax d
	dcr c
	jnz cpyfn3
cpyfn4	equ $+offset
	mov a,b		; check # free blocks
	ora a
	rz
	xra a		; a=0, free block #
cpyfn5	equ $+offset
	inx d
	stax d
	dcr b
	jnz cpyfn5
	ret

; internal subroutine to convert register a (0 thru F) to hexadecimal char
getHexChar equ $+offset
	ani 15
	cpi 10
	jc less
	adi 'A'-'0'-10
less	equ $+offset
	adi '0'
	ret

; send sbuf and get response into rbuf (TODO add retry)
xcv	equ $+offset
	mvi c,3
xcv2	equ $+offset
	push b
	lxi d,sbuf
	call smsg
	lxi d,rbuf
	call rmsg	; a = 0(success)/FF(timeout)
	pop b
	ora a
	rz		; success
	dcr c
	jnz xcv2
	ret		; timeout

; reset record offset params in user's FCB, de = FCB address
resetfcb equ $+offset
	lxi h,12	; EX
	dad d
	mvi m,0
	lxi h,14	; S2
	dad d
	mvi m,0
	lxi h,32	; CR
	dad d
	mvi m,0
	ret

; advance record offset params in user's FCB, de = FCB address
advfcb	equ $+offset
	lhld params
	xchg
	lxi h,32	; CR
	dad d
	inr m
	rp		; return if < 128
	mvi m,0
	lxi h,12	; EX
	dad d
	inr m
	mov a,m
	ani 20h
	rz		; return if < 32
	mvi m,0
	lxi h,14	; S2
	dad d
	inr m
	ret	

; get FCB record count, compute and return file offset in bc
getoffset equ $+offset
	lhld params
	xchg		; de = FCB
	lxi h,32	; CR
	dad d
	mov a,m
	ani 7fh
	mov c,a
	lxi h,12	; EX
	dad d
	mov a,m
	ani 1fh
	rar		; lsb in carry
	mov b,a
	jnc getoff2
	mov a,c
	ori 80h
	mov c,a
getoff2	equ $+offset
	lxi h,14	; S2
	dad d
	mov a,m
	rlc
	rlc
	rlc
	rlc
	ani 0f0h
	ora b
	mov b,a
	ret	

; setup network send buffer
;   call with b=length, c=network command byte, de=FCB address
setupbuf equ $+offset
	mov a,b		; network packet length
	sta sbuf
	mov a,c		; network command
	sta sbuf+1
	mov a,e		; FCB address serves as handle
	sta sbuf+2
	mov a,d
	sta sbuf+3
	ret

; copy # of bytes in c from hl to de
copybytes equ $+offset
	mov a,m		; read byte at hl
	stax d		; write to de
	inx h
	inx d
	dcr c
	jnz copybytes
	ret


	;
	; Search for first
	;
	; Inputs:
	;     de = FCB address
	; Outputs:
	;     a = 0(success)/FF(failure)
	;     writes the returned directory entry to dmaaddr
	;
srchfv	equ $+offset
	mvi a,0ffh
	sta fndactive	; reset Search for next signal
	call isnetdsk	; doesn't return if not network disk

	lhld params
	shld savefcb	; save FCB address for Search for next

	mvi b,10h	; message length
	mvi c,NFNDFST	; network command
	
	call setupbuf

	call getfilename ; copy filename from FCB

	; hl points to EX-1
	inx h
	mov a,m
	sta fndextent	; save extent filter for Search for next

srchret	equ $+offset
	call xcv
	ora a
	rnz		; xcv sets status

srchrt2	equ $+offset
	call copynamedma ; copy matching filename to DMA address

	lda rbuf+4	; status, 0=success, 0xFF=end of directory
	sta fndactive	; if done, signal to Search for next
	sta status
	ret
	

	;
	; Search for next
	;
	; Inputs:
	;     None
	; Outputs:
	;     a = 0(success)/FF(failure)
	;     writes the returned directory entry to dmaaddr
	;
srchnv	equ $+offset
	lda fndactive
	ora a
	jnz  gobdos	; find disk is not network disk

	lhld savefcb	; recover FCB address
	xchg		; move to de

	; If EX was '?', match all extents; else, match only the specified extent
	lda fndextent	; EX byte from Search for first
	cpi '?'
	jnz srchn1	; get the next filename

	; If the file would use multiple extents, we must generate and
	; return each extent to the caller or they cannot compute the
	; correct file size (e.g., STAT.COM counts extents).
	; Presently only handling files with 32 extents (524288 bytes, 512KB)
	lxi h,rbuf+5+11	; extent byte
	dcr m
	jm srchn1	; we reported the last extent, get next filename from server
	inx h
	inx h
	inx h
	mvi m,80h	; this extent will be full
	jmp srchrt2

srchn1	equ $+offset

	mvi b,5		; message length
	mvi c,NFNDNXT	; network command
	; de already contains FCB address (which we use as a file handle)
	
	call setupbuf

	jmp srchret


	;
	; Open file
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(failure)
	;
openfv	equ $+offset
	call isnetdsk	; doesn't return if not network disk

	call resetfcb

	mvi b,10h	; message length
	mvi c,NOPENF	; network command
	; de contains FCB address (which we use as a file handle)

xcvwithfn equ $+offset
	call setupbuf	; setup sbuf header

	call getfilename ; copy filename from FCB

xcvnofn equ $+offset
	call xcv	; send sbuf, get response in rbuf
	ora a
	rnz		; xcv sets status

	lda rbuf+4	; status
	sta status
	ret

	;
	; Delete file
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
deletfv	equ $+offset
	call isnetdsk	; doesn't return if not network disk

	mvi b,10h	; message length
	mvi c,NDELETF	; network command

	jmp xcvwithfn
	

	;
	; Create file
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
creatfv	equ $+offset
	call isnetdsk	; doesn't return if not network disk

	call resetfcb

	mvi b,10h	; message length
	mvi c,NCREATF	; network command

	jmp xcvwithfn


	;
	; Close file
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(failure)
	;
closefv	equ $+offset
	call isnetdsk	; doesn't return if not network disk

	mvi b,5		; message length
	mvi c,NCLOSEF	; network command
	; de contains FCB address (which we use as a file handle)

	call setupbuf	; setup sbuf header

	jmp xcvnofn


	;
	; Read file
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/1(end of file)/FF(failure)
	;
readfv	equ $+offset
	call isnetdsk	; doesn't return if not network disk

	mvi b,7		; message length
	mvi c,NREADF	; network command
	; de contains FCB address (which we use as a file handle)

	call setupbuf	; setup sbuf header

	call getoffset	; get file offset in bc
	mov a,c
	sta sbuf+4
	mov a,b
	sta sbuf+5

	call xcv	; transmit sbuf & get response in rbuf
	ora a
	rnz		; xcv sets status

	lda rbuf+4	; status from server
	ora a
	sta status
	rnz		;jnz return	; return error code

	; copy 128 bytes starting at rbuf+5 to DMA address
	mvi c,128	; # bytes to copy
	lxi d,rbuf+5	; source
	lhld dmaaddr	; destination
	xchg		; de=destination, hl=source
	call copybytes	; copy c bytes from de to hl

	call advfcb	; increment record offset in FCB
	ret


	;
	; Write file
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
writefv	equ $+offset
	call isnetdsk	; doesn't return if not network disk

	mvi a,3
	sta retry	; init retry counter

writef1	equ $+offset
	mvi b,135	; message length
	mvi c,NWRITEF	; network command
	; de contains FCB address (which we use as a file handle)
	
	call setupbuf	; setup sbuf header
	
	call getoffset	; get file offset in bc
	mov a,c
	sta sbuf+4
	mov a,b
	sta sbuf+5

	; copy 128 bytes starting at DMA address to sbuf+6
	mvi c,128	; # bytes to copy
	lhld dmaaddr	; source
	lxi d,sbuf+6	; destination
	call copybytes

	call xcv	; send sbuf, get response in rbuf

	ora a		; a=0(success)/FF(timeout)
	;jnz writef2
	rnz		; error
	lda rbuf+4	; status from server
	ora a
	sta status
	rnz		; error

	call advfcb	; advance current record counter in FCB
	ret

	; TODO move retries to xcv

;writef2	equ $+offset
;	lda retry
;	dcr a
;	jz c1
;	sta retry
;	lxi h,0
;
;writef3	equ $+offset
;	inx h
;	mov a,h
;	ora l
;	jnz writef3	; wait for a while
;	lhld params
;	xchg		; de = FCB address
;	jmp writef1	; send the request again
;
;c1	equ $+offset
;	mvi a,0ffh
;	sta status
;	ret


	;
	; Rename file
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
renamfv	equ $+offset
	call isnetdsk	; doesn't return if not network disk

	mvi b,27	; message length
	mvi c,NRENAMF	; network command
	; de contains FCB address (which we use as a file handle)

	call setupbuf	; setup sbuf header

	call getfilename ; old filename

	lhld params	; hl = FCB address
	lxi d,16
	dad d		; hl = FCB + 16
	lxi d,sbuf+4+11  ; destination
	call getfn1	; new filename

	jmp xcvnofn


	;
	; Set random record
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     random record fields in FCB
	;
setrrv	equ $+offset
	call isnetdsk	; doesn't return if not network disk

	; Read S2(14), EX(12), and CR(32) from FCB
	call getoffset	; get file offset in bc

	; Store bc in r0(33),r1(34),r2(35) in FCB
	lxi h,33	; offset to r0
	dad d
	mov m,c		; low-byte
	inx h
	mov m,b		; high-byte
	inx h
	mvi m,0		; overflow
	ret
	

	;
	; Compute file size
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     random record fields in FCB
	;
getszv	equ $+offset


	;
	; Set file attributes
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
setatrv	equ $+offset



	;
	; Read random
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
readrv	equ $+offset


	;
	; Write random
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
writerv	equ $+offset


	;
	; Write random w/zero fill
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
wrtrfv	equ $+offset


	; Panic exit
	call isnetdsk	; doesn't return if not network disk

	mov a,c		; convert function code to hexadecimal
	rrc
	rrc
	rrc
	rrc
	call getHexChar
	sta panicarg
	mov a,c
	call getHexChar
	sta panicarg+1	
	mvi c,prnstr
	lxi d,panicmsg
	call 5

	; We are aborting the program because it's trying to do
	; something we don't support.
	jmp warmv	; jump to BIOS warm start



lastaddr equ $+offset
	
	end

