;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NDOS.ASM
;; 
;; To build NDOS.SPR:
;;   RMAC NDOS $PZ SZ
;;   LINK NDOS[OS]
;;
;; This file assembles to NDOS.SPR which is a page relocatable
;; file meant to run just below the NIOS.SPR which itself
;; is meant to run just below the BDOS.
;;
;; +-----------------+
;; | BIOS            |
;; +-----------------+
;; | BDOS            |
;; +-----------------+
;; | NIOS            |
;; +-----------------+
;; | NDOS            |
;; +-----------------+
;; | TPA             |
;; |                 |
;; +-----------------+
;; | 0005 JMP NDOS+6 |
;; +-----------------+
;; | 0000 JMP BIOS   |
;; +-----------------+
;;
;;
;; The NDOS loader loads the NIOS.SPR into the pages just below
;; the BDOS and loads the NDOS.SPR into the pages just below
;; the NIOS. The NDOS finds the NIOS jump table by assuming
;; that the very next page following NDOS is NIOS. After the loader
;; fixes-up all of the relocation bytes, it jumps to the NDOSCOLD
;; entry (NDOS+9). The NDOS updates the BDOS vector on page 0
;; to point to the NDOS which protects the NDOS and BIOS from
;; being overwritten by other transient programs. NDOS also updates
;; the BIOS jump table to point the warm start to the warm
;; entry so that NDOS can load the CCP.
;;
;; NDOS requires a relocatable CCP.COM on drive A.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	maclib	ndos

NDOSVER equ 11h		; packed binary coded decimal
NDOSDSK	equ 15		; drive P is the network drive
RETRYCNT equ 3          ; number of transceive attempts before failure

	; NIOS entry points
NIOSINIT	equ	0
NIOSSMSG	equ	3
NIOSRMSG	equ	6
NIOSSTAT	equ	9

FCB?EX		equ	12	; extent (0-31)
FCB?S2		equ	14	; extent counter (0-15)
FCB?RC		equ	15	; records used in this extent (0-127)
FCB?CR		equ	32	; current record in this extent (0-127)
FCB?R0		equ	33	; low-byte of random record #
FCB?R1		equ	34	; high-byte of random record #
FCB?R2		equ	35 	; overflow of R1
	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; Resident Network DOS image starts here
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
firstaddr:
	; This makes CCP.COM happy
	db 0,22,0,0,0,0	; serial number 

entry:  jmp begin	; standard entry point
	jmp cold	; cold start entry - hook vectors & init NIOS
	jmp warm	; warm start entry - load CCP.COM

	; bdosadr and warmst are set by cold from page 0 values
	; before cold redirects BDOS calls to NDOS and hooks
	; the BIOS warm start vector in the jump table.

bdosadr:jmp 0		; Original BDOS address

warmst:	hlt		; Original BIOS Warm Start - The BIOS
	dw 0		; reloads the BDOS and original CCP from
			; the system tracks. Don't call/jmp here
			; without restoring the BIOS warm start
			; in the BIOS jump table or the next
			; warm start will crash the system because
			; NDOS will be gone.

restore:jmp remove	; Restore vectors & unload NDOS

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; local variables
fcb:
	db	1,'CCP     COM',0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0 ; cr

noccpmsg:
	db	cr,lf,'CCP.COM not found',cr,lf
	db	'$'

filed:
	db	cr,lf,'CCP.COM loaded',cr,lf
	db	'$'

panicmsg:
	db	cr,lf,cr,lf,'**** NDOS panic '
panicarg:
	db	'XX ****',cr,lf
	db	'$'

functbl:
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
functblend:

nfuncs	equ (functblend-functbl)/2

;
; Fake disk parameter block 
;
dpb:
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
alvs:
	db 0ffh,0ffh
	; In the eventuality that an app requires drive space to run
	; the two bytes above plus the following are needed fo DSM = 242.
	;db     0,0,0,0,0,0, 0,0,0,0,0,0,0,0
	;db 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0
	;db 0

sbuf:
	ds 	140		; network send buffer

rbuf:
	ds 	140		; network receive buffer

active:
	db 	0		; current default drive

params:
	dw 	0		; de input parameter

dmaaddr:
	dw 	0		; the DMA address

savefcb:
	dw 	0		; FCB address for Search for next

fndactive:
	db 	0ffh		; flag for Search for next

fndextent:
	db 	0		; Search file extent flag

status:
	dw	0		; return code

userstk:
	dw	0		; storage for user stack pointer

niospage:
	db	0		; page where NIOS starts

biospage:
	db	0		; page where BIOS starts

backupser:
	db 0,22,0,0,0,0	; backup serial number 

	ds	16
stack:				; NDOS stack

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NDOS cold start entry point - NDOS/NIOS loader jumps here
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
cold:   lda	niospage	; check if this is first time
	ora 	a
	jnz	doinit        	; if we are already loaded, just init NIOS

	lxi	h,lastaddr	; get last byte of NDOS
	mov	a,h             ; a = last page of NDOS
	inr	a		; a = first page of NIOS
	sta 	niospage

	lhld	bdosv+1		; get BDOS entry address
	shld	bdosadr+1	; save original BDOS entry locally

	lxi	d,warm  	; DE points to our warm start
	lhld	warmv+1		; get BIOS warm start
	inx	h		; skip JMP byte in BIOS jump table
	mov	a,m		; low-byte of warm start function
	sta	warmst+1
	mov	m,e		; update BIOS jump table
	inx	h
	mov	a,m		; high-byte
	sta	warmst+2
	mov	m,d		; update BIOS jump table

	mov	a,h		; BIOS page
	sta	biospage

doinit: call	init 		; initialize the NIOS
	; TODO check the return value...

	; fall through to warm start

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NDOS warm start entry point - the BIOS hook comes here
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
warm:   lxi sp,stack	; set stack pointer

	mvi a,0c3h	; JMP opcode
	sta warmv
	sta bdosv
	lxi h,entry	; get NDOS entry address
	shld bdosv+1	; update BDOS vector so we are protected
	lda biospage
	mov h,a
	mvi l,3
	shld warmv+1

	;
	; Load CCP.COM from default drive
	;
	mvi a,76h	; opcode for HLT
	sta tpa		; store HLT in TPA in case load fails
	xra a
	mvi c,openf
	lxi d,fcb
	call resetfcb	; set S2=EX=CR=0
	call bdosadr
	inr a
	jz noccp
	lxi d,tpa
loadloop:
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

done:
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
	; Copy six serial number bytes from backup
	; Some programs overwrite the serial number (probably stack) 
        ; which causes CCP.COM to HALT when trying to load a transient program
        ;
	mvi c,6
	lxi h,backupser ; backup serial number
	lxi d,firstaddr	; start of NDOS
	call copybytes

	jmp tpa		; start CCP

noccp:	mvi c,prnstr
	lxi d,noccpmsg
	call bdosadr
        
        ; fall-through to remove


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NDOS kill entry point - removes BDOS and BIOS hooks & warm starts
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
remove:	lhld warmv+1	; get BIOS warm start vector
	inx h		; skip JMP byte
	lda warmst+1	; get old BIOS warm start
	mov m,a		; update BIOS jump table
	inx h
	lda warmst+2
	mov m,a		; update BIOS jump table	
	rst 0		; warm start!

	
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; BDOS/NDOS entry point - the BDOS hook comes here
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
begin:	xchg		; swap de into hl
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
	cpi n?ver
	jz retver
	cpi n?smsg
	jz smsg
	cpi n?rmsg
	jz rmsg
	cpi n?stats
	jz retstats
	cpi n?init
	jz init

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
	; Return status to caller - NDOS calls return through here
	;
return:
	lhld userstk	; recover user stack pointer into hl
	sphl		; set sp from hl
	lhld status
	mov b,h
	mov a,l
	ret


	;
	; We don't handle the function, send it to BDOS
	;
gobdos:
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
retver:	mvi a,NDOSVER
	sta status
	ret


	;
	; Initialize the network
	;
	; Inputs:
	;     None
	; Outputs:
	;     a = 0(success)/FF(failure)
	;
init:   mvi	a,NIOSINIT

	; fall-through to gonios

gonios:	lxi	h,savestatus
	push	h		; push return address
	mov	l,a
	lda	niospage
	mov	h,a
	pchl			; jump to NIOS function

savestatus:
	shld	status		; save status
	ret			; a = 0(success)/FF(failure)


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
smsg:	mvi	a,NIOSSMSG
	jmp	gonios


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
rmsg:	mvi	a,NIOSRMSG
	jmp	gonios


	;
	; Return pointer to packet stats
	;
	; Inputs:
	;     None
	; Outputs:
	;     hl = pointer
	;
retstats:
	mvi	a,NIOSSTAT
	jmp	gonios


	;
	; Set DMA address
	;
	; Inputs:
	;     de = DMA address
	; Outputs:
	;     None
	;
setdmav:
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
rstdskv:
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
seldskv:
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
getdskv:
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
dskprmv:
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
allocv:
	lda active
	cpi NDOSDSK	; is it our disk #?
	jnz  gobdos	; unknown drive, let bdos handle it
	lxi h,alvs
	shld status
	ret


; internal subroutine to check if FCB at de is selecting the network disk
isnetdsk:
	ldax d		; get drive select from FCB
	ora a		; is default drive & current user selected?
	jz checkactive
	cpi '?'		; is default drive & all users selected?
	jz checkactive
	dcr a		; convert 1-16 to 0-15
	jmp checkdisk
checkactive:
	lda active	; get selected disk #
checkdisk:
	cpi NDOSDSK
	rz		; the network disk is selected, return
	pop h		; remove return address from stack
	jmp  gobdos	; goto BDOS


; internal subroutine to copy filename from FCB at de into sbuf+4
getfilename:
	lhld params	; hl = FCB address
	lxi d,sbuf+4	; destination
getfn1:
	mvi c,11	; filename & extension
	; ignoring bytes dr (byte 0 of FCB) and ex (byte 12)
getfn2:
	inx h
	mov a,m		; get byte from FCB
	stax d		; write byte to sbuf
	inx d
	dcr c
	jnz getfn2
	ret

; internal subroutine to copy filename from rbuf+5 into DMA
copynamedma:
	lhld dmaaddr
	xchg		; de is destination
	xra a
	stax d		; set user code to 0
	lxi h,rbuf+5	; hl is source
	mvi c,15	; get filename, extension, ex, s1, s2, & rc
	inx d
	call copybytes

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
cpyfn2:
	mov a,c
	ora a
	jz cpyfn4
	mvi a,3		; use a non-zero block #
cpyfn3:
	inx d
	stax d
	dcr c
	jnz cpyfn3
cpyfn4:
	mov a,b		; check # free blocks
	ora a
	rz
	xra a		; a=0, free block #
cpyfn5:
	inx d
	stax d
	dcr b
	jnz cpyfn5
	ret

; internal subroutine to convert register a (0 thru F) to hexadecimal char
getHexChar:
	ani 15
	cpi 10
	jc less
	adi 'A'-'0'-10
less:
	adi '0'
	ret

; send sbuf and get response into rbuf - if there is an error on receive,
; the request is retried.
; This only works because all requests are idempotent, even read & write
; because they include the seek offset in the request.
xcv:
	mvi c,RETRYCNT  ; C= # of retries
xcv2:
        push b          ; save retry counter
	lxi d,sbuf
	call smsg	; updates status, a = 0(success)/FF(timeout)
	lxi d,rbuf
	call rmsg	; updates status, a = 0(success)/FF(timeout)
	pop b           ; restore retry counter
	ora a
	rz		; success
	dcr c           ; decrement retry counter
	jnz xcv2
	ret		; timeout or checksum error

; reset record offset params in user's FCB, de = FCB address
resetfcb:
	xra a
	lxi h,FCB?EX
	dad d
	mov m,a
	lxi h,FCB?S2
	dad d
	mov m,a
	lxi h,FCB?CR
	dad d
	mov m,a
	ret

; advance record offset params in user's FCB, de = FCB address
advfcb:
	lhld params
	xchg
	lxi h,FCB?CR
	dad d
	inr m		; most-sig bit selects next extent on read/write
	ret	

; get FCB record count, compute and return file offset in bc
getoffset:
	lhld params
	xchg		; de = FCB
	lxi h,FCB?CR
	dad d		; hl points to CR
	mov a,m
	mov c,a		; c = current record
	ora a
	jp getoff1      ; check for overflow of CR
	;
	; on overflow of CR, select next extent
	mvi m,0		
	mvi c,0		; c = record 0 of new extent
	lxi h,FCB?EX
	dad d
        inr m		; select next EX
	mov a,m
	ani 20h		; check for overflow
	jz getoff1
	mvi m,0		; clear overflow of EX
	lxi h,FCB?S2
	dad d
	inr m		; increment S2

        ; c = current record modulus 128, now combine S2 and EX into b and move LSB of EX into c
getoff1:
	lxi h,FCB?EX
	dad d		; hl points to EX
	mov a,m
	ani 1fh
	clc
	rar		; lsb of EX in carry
	mov b,a		; b is now most sig. 4-bits of EX
	jnc getoff2
	mov a,c
	ori 80h		; c = ((EX & 1)<<7) | (CR & 7Fh)
	mov c,a
getoff2:
	lxi h,FCB?S2
	dad d		; hl points to S2
	mov a,m
	rlc
	rlc
	rlc
	rlc
	ani 0f0h	; a = S2 << 4
	ora b
	mov b,a		; b = (S2 << 4) | (EX >> 1)
	ret	

; return bc = random record counter from FCB
; update FCB S2, EX, and CR
getroffset:
	lhld	params
	xchg			; de = FCB
	lxi	h,FCB?R0
	dad	d		; hl points to R0
	mov	c,m		; c = R0
	inx	h
	mov	b,m		; b = R1
	; TODO R2 is overflow from R1, we should return an error if R2 is non-zero...
	lxi	h,FCB?CR
	dad	d		; hl points to CR
	mov	a,c
	ani	07Fh
	mov	m,a		; save CR
	lxi	h,FCB?EX
	dad	d		; hl points to EX
	mov	a,c
	ral			; carry is most-sig bit of CR
	mov	a,b
	ral			; shift carry into EX
	ani	1Fh
	mov	m,a		; save EX
	lxi	h,FCB?S2
	dad	d		; hl points to S2
	mov	a,b
	rar
	rar
	rar
	rar
	ani	0Fh
	mov	m,a		; save S2
	ret

; setup network send buffer
;   call with b=length, c=network command byte, de=FCB address
setupbuf:
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
copybytes:
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
srchfv:
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

srchret:
	call xcv
	ora a
	rnz		; xcv sets status

srchrt2:
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
srchnv:
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

srchn1:

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
openfv:
	call isnetdsk	; doesn't return if not network disk

	call resetfcb

	mvi b,10h	; message length
	mvi c,NOPENF	; network command
	; de contains FCB address (which we use as a file handle)

xcvwithfn:
	call setupbuf	; setup sbuf header

	call getfilename ; copy filename from FCB

xcvnofn:
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
deletfv:
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
creatfv:
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
closefv:
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
readfv:
	call	isnetdsk	; doesn't return if not network disk
	call	getoffset	; bc = file offset from FCB S2,EX,CR
	call	netread
	rnz			; error
	jmp	advfcb		; auto-advance the FCB record counters

	; send network file read, bc=file offset
netread:
	push	b
	mvi	b,7		; message length
	mvi	c,NREADF	; network command
	; de contains FCB address (which we use as a file handle)

	call	setupbuf	; setup sbuf header

	pop	b		; get file offset in bc
	mov	a,c
	sta	sbuf+4
	mov	a,b
	sta	sbuf+5

	call	xcv		; transmit sbuf & get response in rbuf
	ora	a
	rnz			; xcv sets status

	lda	rbuf+4		; status from server
	sta	status
	ora	a		; set/clear Z flag
 	rnz			; return error code

	; copy 128 bytes starting at rbuf+5 to DMA address
	mvi	c,128		; # bytes to copy
	lxi	d,rbuf+5	; source
	lhld	dmaaddr		; destination
	xchg			; de=destination, hl=source
	call	copybytes	; copy c bytes from de to hl
	xra	a
	ret

	;
	; Write file
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
writefv:
	call	isnetdsk	; doesn't return if not network disk
	call	getoffset	; bc = file offset from FCB S2,EX,CR
	call	netwrite	; returns a = status
	rnz			; error
	jmp	advfcb		; auto-advance FCB to next record 

netwrite:
	push	b		; save file offset
	mvi	b,135		; message length
	mvi	c,NWRITEF	; network command
	; de contains FCB address (which we use as a file handle)
	
	call	setupbuf	; setup sbuf header
	
	pop	b		; get file offset in bc
	mov	a,c
	sta	sbuf+4
	mov	a,b
	sta	sbuf+5

	; copy 128 bytes starting at DMA address to sbuf+6
	mvi	c,128		; # bytes to copy
	lhld	dmaaddr		; source
	lxi	d,sbuf+6	; destination
	call	copybytes

	call	xcv		; send sbuf, get response in rbuf

	ora	a		; a=0(success)/FF(timeout)
	rnz			; error
	lda	rbuf+4		; status from server
	sta	status
	ora	a		; set/clear Z flag
	ret



	;
	; Rename file
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
renamfv:
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
setrrv:
	call isnetdsk	; doesn't return if not network disk

	; Read S2(14), EX(12), and CR(32) from FCB
	call getoffset	; get file offset in bc

	; Store bc in r0(33),r1(34),r2(35) in FCB
	lxi h,FCB?R0	; offset to r0
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
getszv:
	jmp	panic


	;
	; Set file attributes
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
setatrv:
	jmp	panic



	;
	; Read random
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
readrv:
	call	isnetdsk	; doesn't return if not network disk
	call	getroffset	; bc = file offset from FCB R0,R1,R2
	jmp	netread


	;
	; Write random
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
writerv:
	call	isnetdsk	; doesn't return if not network disk
	call	getroffset	; bc = file offset from FCB R0,R1,R2
	jmp	netwrite


	;
	; Write random w/zero fill
	;
	; Inputs:
	;     de = FCB
	; Outputs:
	;     a = 0(success)/FF(error)
	;
wrtrfv:
	jmp	panic


	; Panic exit
panic:	call isnetdsk	; doesn't return if not network disk

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
	jmp warm	; reload CCP.COM

lastaddr:

	end

