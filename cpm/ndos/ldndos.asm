;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; LDNDOS.ASM
;;
;; To build LDNDOS.COM:
;;   MAC LDNDOS
;;   LOAD LDNDOS
;;
;; This is the loader for NIOS.SPR and NDOS.SPR. If NDOS is
;; already running, then LDNDOS resets the network stack.
;; Use the /K argument to unload NDOS.
;;
;; If a filename argument is provided, then LDNDOS will
;; load the referenced file as the NIOS. For example,
;;
;; A>LDNDOS                 [loads NIOS.SPR and NDOS.SPR]
;;
;; A>LDNDOS KP-NIOS.SPR     [loads KP-NIOS.SPR and NDOS.SPR]
;;
;; A>LDNDOS /K              [unload NDOS and NIOS and warm boot]
;;

	maclib	ndos

	org	tpa
        
        lxi     h,0
        dad     sp              ; hl = sp
        shld    savestack       ; save original stack pointer
        lxi     sp,stack

	;
	; Parse command line
	;
	lda	defdma		; command argument length
	ora	a
	jz	chkndos

	; look for /K in args
	mov	c,a		; c=count
	lxi	h,defdma+1	; first char
loop:	mov	a,m
	cpi	'/'
	jnz	nextchar
	inx	h
	dcr	c
	jz	chkndos
	mov	a,m
	cpi	'K'
	jnz	nextchar
	sta	unload		; signal kill command
	jmp	chkndos

nextchar:
	inx	h
	dcr	c
	jnz	loop

	;
	; Is NDOS loaded?
	;

chkndos:
	mvi	c,n?ver
	call 	bdosv
	ora	a
	jz	doload		; BDOS returns 0 when NDOS is not loaded

	; a= NDOS version
	push	psw
	ani	15
	adi	'0'
	sta	version+2
	pop	psw
	rrc
	rrc
	rrc
	rrc
	ani	15
	adi	'0'
	sta	version

	mvi	c,prnstr
	lxi	d,signon
	call	bdosv

	lda	unload		; NDOS is loaded, check unload flag
	ora	a
	jnz	dounload

	;
	; Cold-start NDOS which hooks BDOS & BIOS vectors and inits the NIOS
	;
	lhld	bdosv+1
	mvi	l,NDOSCOLD
	pchl			; jump to cold start

	;
	; Remove NDOS from memory
	;

dounload:
	mvi	c,prnstr
	lxi	d,removed
	call	bdosv

	lhld	bdosv+1
	mvi	l,NDOSKILL
	pchl			; jump to kill NDOS

	;
	; Load NIOS and NDOS and cold start NDOS
	;
doload:
	lda	unload		; check for kill command
	ora	a
	jz	doload2

	mvi	c,prnstr        ; NDOS isn't loaded, can't kill it
	lxi	d,notloaded
        call    bdosv
        
        lhld    savestack
        sphl                    ; sp = hl
        ret                     ; quit



	; first, load the NIOS.SPR
doload2:
	mvi	c,prnstr
	lxi	d,startup
	call	bdosv
	mvi	c,prnstr
	lxi	d,copyrgh
	call	bdosv

	lda	defdma		; check for command line args
	ora	a
	lxi	d,niosfcb	; select NIOS internal filename
	jz	doload3
	lxi	d,deffcb        ; select NIOS filename from command line

doload3:
	lda	bdosv+2         ; BDOS page
	sta	bdospage
	xchg                    ; hl = NIOS fcb address
	shld    fcb
        
        mov     h,a
        mvi     l,0
        lxi     d,bdosstr       ; print BDOS page
        call    prnvector
                
	call	install         ; load file referenced by fcb and relocate

	lda	newpage         ; NIOS page
	sta	bdospage
	lxi	d,ndosfcb
	xchg
	shld	fcb
        
        mov     h,a
        mvi     l,0
        lxi     d,niosstr       ; print NIOS page
        call    prnvector
      
	call	install

	lda	newpage		; NDOS page
        push    psw

        mov     h,a
        mvi     l,0
        lxi     d,ndosstr       ; print NDOS page
        call    prnvector

        pop     psw             ; pop h?
	mov	h,a
	mvi	l,NDOSCOLD	; NDOS cold start
	pchl			; jump into NDOS


	;
	; SPR file installer, load file at fcb
	;
install:mvi	c,openf
	lhld	fcb
	xchg
	call	bdosv		; open NIOS.SPR
	inr	a
	jz	not?found
	lxi	d,buffer
loadloop:
	push	d		; save buffer address
	mvi	c,setdma
	call	bdosv		; set DMA to buffer
	mvi	c,readf
	lhld	fcb
	xchg
	call	bdosv		; read 128 bytes
	pop	h		; recover buffer address
	ora	a
	jnz	done
	lxi	d,128
	dad	d
	xchg			; swap hl and de
	jmp	loadloop

done:	mvi	c,closef
	lhld	fcb
	xchg
	call	bdosv

	; now, relocate the image to upper memory
	lhld	buffer+1	; size of NIOS image
	xchg			; de = size of image

	mov	b,d		; b = high-byte of size
	inr	b		; b = #pages of image
	lda	bdospage	; a = BDOS page
	sub     b		; a = new top of TPA page
	sta	newpage
	mov	b,a
	mvi	c,0		; bc = destination

	lxi	h,buffer+256	; hl = image source
	push	h		; save hl
	dad	d		; hl = start of relocation bitmap
	mvi	a,80h		; start with bit 7
	sta	bitmask
moveloop:
	lda	bitmask
	ana	m		; check relocation bitmap @hl
	xthl			; hl = image source
	mov	a,m		; get image byte
	jz      nextbyte	; mov and xthl don't affect zero flag
	lda	newpage
	add	m
nextbyte:
	stax	b		; write to destination
	inx	h		; ++image source
	xthl			; hl = relocation bitmap
	inx	b               ; ++destination
	dcx	d               ; --count
	lda	bitmask
	rrc			; bit 0 rotates into bit 7 and Carry
	sta	bitmask
	jnc	checkdone
	inx	h               ; next byte in relocation bitmap
checkdone:
	mov	a,d
	ora	e
	jnz	moveloop

	pop	h		; clean-up stack

	ret


	; Print file not found error
not?found:
	mvi	c,prnstr
	lxi	d,error
	call	bdosv

	rst	0		; warm start because CCP is probably gone!


; Print string at de, then vector value in hl, then CRLF
prnvector:
        push    h
        mvi     c,prnstr
        call    bdosv
        pop     h
        call    prnword
prncrlf:mvi     c,prnstr
        lxi     d,crlf
        jmp     bdosv

; Print value in A as hexadecimal character
prnchar:
	ani 0fh
	cpi 10
	jc less
	adi 'A'-'0'-10
less:	adi '0'
	mvi c,conout	; console output
	mov e,a
	call bdosv
	ret


; Print value in HL in hexadecimal
prnword:
	mov a,h
	rrc
	rrc	
	rrc
	rrc
	push h
	call prnchar

	pop h
	mov a,h
	push h
	call prnchar

	pop h
	mov a,l
	rrc
	rrc
	rrc
	rrc
	push h
	call prnchar

	pop h
	mov a,l
	call prnchar

	ret

        
crlf:	db cr,lf,'$'


bdosstr:db 'BDOS : $'
niosstr:db 'NIOS : $'
ndosstr:db 'NDOS : $'



fcb:	dw	0       	; points to FCB

niosfcb:db	0,'NIOS    SPR',0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0  ; current record

ndosfcb:db	0,'NDOS    SPR',0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0  ; current record

error:
	db	'NIOS.SPR or NDOS.SPR not found',cr,lf
	db	'Specify the NIOS file as: LDNDOS <nios>.SPR',cr,lf,'$'

loaded:
	db	'NDOS loaded',cr,lf,'$'

already:
	db	'NDOS already loaded',cr,lf,'$'

notloaded:
	db	'NDOS not loaded',cr,lf,'$'

removed:
	db	'NDOS removed',cr,lf,'$'

signon:	db	'NDOS '
version:db	'x.y',cr,lf
copyrgh:db	'Copyright (c) 2019-20 Erik Petersen',cr,lf,'$'
startup:db	'Loading NDOS and NIOS',cr,lf,'$'

newpage:
	db	0

bitmask:db	0

bdospage:
	dw	0

unload:	db	0

savestack:
        dw      0
        
        ds      16
stack:

	; read SPR files into buffer starting here
buffer:
	end

