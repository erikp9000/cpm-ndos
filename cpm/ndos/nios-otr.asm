;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NIOS-OTR.ASM   [Otrona Attache]
;;
;; To build NIOS-OTR.SPR:
;;   RMAC NIOS-OTR $PZ SZ
;;   LINK NIOS-OTR[OS]
;;
;; The Otrona Attache NIOS uses 'J302 Serial Port A' to
;; communicate with the file service. The baud rate is
;; 19.2Kbps (max).
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	maclib	ndos

DCOMM   equ     0f0h            ; data register
SCOMM   equ     0f1h            ; control/status register
BAUDC   equ     0f4h            ; counter timer chip

; Receive byte timeout counter
RECVTMO	equ	32768

        ;
	; Jump table used by NDOS to access network functions
        ; (Don't put any code/data before these or NDOS will be broken.)
        ;
	jmp	init
	jmp	smsg
	jmp	rmsg
	jmp	nstat

        ; return success/failure code

success:lxi	h,0
	mov	a,l
	ret

failure:lxi	h,0ffh
	mov	a,l
	ret

	; network statistics counters

sentcnt:dw	0		; count of messages sent
recvcnt:dw	0		; count of messages received
tocnt:	dw	0	        ; count of timed-out messages
chkcnt:	dw	0		; count of messages with bad checksum

	;
	; Initialize the network
	;
	; Inputs:
	;     None
	; Outputs:
	;     a = 0(success)/FF(failure)
	;     l = a
	;     h = 0
init:   lxi     h,0
        shld    sentcnt
        shld    recvcnt
        shld    tocnt
        shld    chkcnt
        
        mvi     a,057h          ; 
        out     BAUDC
        mvi     a,1             ; select 19200 bps
        out     BAUDC
        
        jmp     success


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
smsg:	ldax	d		; LEN
	mvi	b,0		; B = checksum register
	mov	c,a             ; C = LEN
	ora	a
	jz	failure

txbusy: in      SCOMM
        ani     4
        jz      txbusy        
        
	ldax	d               ; get byte
	out	DCOMM	        ; send it
	add	b		; add it to checksum
	mov	b,a		; store in checksum register

	inx	d		; advance to next byte
	dcr	c		; decrement byte counter
	jz	sdone
	mov	a,c
	cpi	1
	jnz	txbusy		; keep sending bytes

	mov	a,b		; get checksum
	cma			; A = NOT A
	inr	a		; compute 2's complement
	stax	d
	jmp	txbusy		; send checksum

sdone:	lhld	sentcnt
	inx	h
	shld	sentcnt
	jmp	success


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
rmsg:   call	recvbyte
	jc	rmsgto

	mvi	b,0		; init checksum
	mov	c,a		; c = LEN

nextbyte:
	stax	d		; write byte to buffer
	inx	d		; advance buffer pointer
	add	b		; A = A + B
	mov	b,a		; B = A
	dcr	c
	jz	recvchk		; verify checksum

	call	recvbyte
	jnc	nextbyte

rmsgto:	lhld	tocnt		; timeout
	inx	h
	shld	tocnt
	jmp	failure

recvchk:ora	a
	jnz	recvbad

	lhld	recvcnt
	inx	h
	shld	recvcnt
	jmp	success		; message is OK

recvbad:lhld	chkcnt 		; bad checksum
	inx	h
	shld	chkcnt
	jmp	failure

	; carry flag is set on timeout
recvbyte:
	lxi	h,RECVTMO

recvwait:
        in      SCOMM
        ani     1
	jnz	readbyte
	dcx	h
	mov	a,h
	ora	l
	jnz	recvwait
	stc			; timeout
	ret

readbyte:
	in	DCOMM
	clc
	ret


	;
	; Return pointer to packet stats
	;
	; Inputs:
	;     None
	; Outputs:
	;     hl = pointer
	;
nstat:	lxi h,sentcnt
	ret

