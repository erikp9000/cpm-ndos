;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; ALTRNIOS.ASM   [Altair 8800 w/88-2SIO serial port]
;;
;; To build ALTRNIOS.SPR:
;;   RMAC ALTRNIOS $PZ SZ
;;   LINK ALTRNIOS[OS]
;;
;; The Altair 8800 NIOS uses the second serial port on the 
;; 88-2SIO to communicate with the file server. The baud
;; rate is jumper configurable; 9600 bps is the highest rate.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	maclib	ndos

SIOCTLR	equ	12h		; control register (write only)
  BAUD0	equ	001h		;   0=/1, 1=/16, 2=/64, 3=reset
  BAUD1 equ	002h
  PAR	equ	004h		;   parity (even/odd)
  STOP	equ	008h            ;   stop bits (2/1)
  BITS	equ	010h            ;   data bits (7/8)
  RTS0	equ	020h
  RTS1	equ	040h
  INTE	equ	080h
SIOSTAT	equ	12h		; status register (read only)
  RDRF	equ	001h		;   receive data available
  TDRE	equ	002h		;   transmit buffer empty
  DCD	equ	004h		;   -Data carrier detect
  CTS	equ	008h		;   -Clear to send
  FE	equ	010h		;   framing error
  OVRN	equ	020h		;   receiver overrun
  PE	equ	040h		;   parity error
  IRQ	equ	080h		;   interrupt request
SIODATA	equ	13h		; data register (read/write)

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

	in	SIODATA		; reset RDRF

txbusy:	in      SIOSTAT
	ani	TDRE
	jz	txbusy
	ldax	d               ; get byte
	out	SIODATA	        ; send it
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
	in	SIOSTAT
	ani	RDRF
	jnz	readbyte
	dcx	h
	mov	a,h
	ora	l
	jnz	recvwait
	stc			; timeout
	ret

readbyte:
	in	SIODATA
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

