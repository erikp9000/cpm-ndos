;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NIOS-T80.ASM   [TRS-80 Model 4/4P/4D]
;;
;; To build NIOS-T80.SPR:
;;   RMAC NIOS-T80 $PZ SZ
;;   LINK NIOS-T80[OS]
;;
;; The TRS-80 Model 4 NIOS uses the P1 DB-25 RS-232 port
;; to communicate with the file server. The default rate is
;; 19.2Kbps (max). Model 4/4P/4D should all be supported.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	maclib	ndos

; Receive byte timeout counter
RECVTMO	equ	32768           ; reasonable receive timeout for 4MHz

UARTMR          equ     0E8H    ; Write-only, Master reset

MODSTAT         equ     0E8H    ; Read-only, Modem status
  RI            equ     010H    ; DB25 pin 22
  CD            equ     020H    ; DB25 pin 8
  DSR           equ     040H    ; DB25 pin 6
  CTS           equ     080H    ; DB25 pin 5

UARTBAUD        equ     0E9H    ; Write-only, Baud rate control
  BAUD50        equ     00H
  BAUD75        equ     11H
  BAUD110       equ     22H
  BAUD134       equ     33H
  BAUD150       equ     44H
  BAUD300       equ     55H
  BAUD600       equ     66H
  BAUD1200      equ     77H
  BAUD1800      equ     88H
  BAUD2000      equ     99H
  BAUD2400      equ     0AAH
  BAUD3600      equ     0BBH
  BAUD4800      equ     0CCH
  BAUD7200      equ     0DDH
  BAUD9600      equ     0EEH
  BAUD19200     equ     0FFH 

UARTCNTL        equ     0EAH    ; Write-only, Modem control
  RTS           equ     001H    ; DB25 pin 4
  DTR           equ     002H    ; DB25 pin 20
  TD?ENB        equ     004h    ; DB25 pin 2 (TD) - low is BREAK
  SRTS          equ     008h    ; DB25 pin 19
  PI            equ     008H    ; Parity inhibit; 0=parity, 1=no parity
  SBS           equ     010H    ; 0=1 stop bit; 1=2 stop bits
  WLS2          equ     020H    ; WLS2 WLS1
  WLS1          equ     040H    ;  0    0  =5 data bits
                                ;  0    1  =6 data bits
                                ;  1    0  =7 data bits
                                ;  1    1  =8 data bits
  EPE           equ     080H    ; Even parity enable; 0=odd, 1=even

UARTSTAT        equ     0EAH    ; Read-only, UART status
  PE            equ     008H    ; Parity error
  FE            equ     010H    ; Framing error
  OE            equ     020H    ; Overrun error
  THRE          equ     040H    ; Transmit holding register empty
  DR            equ     080H    ; Receive data ready
 
UARTDATA        equ     0EBH    ; Read/write
 
  
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
init:	mvi	a,BAUD19200     ; 0fh
	out	UARTBAUD	; 19.2 Kbps
        
        out     UARTMR          ; reset UART
        
        mvi     a,PI OR WLS1 OR WLS2 OR TD?ENB    ; 8N1
        out     UARTCNTL
        
        lxi     h,0
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

txbusy:	in      UARTSTAT
	ani	THRE
	jz	txbusy
	ldax	d               ; get byte
	out	UARTDATA        ; send it
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
	jnc	nextbyte        ; carry is set on timeout

rmsgto:	lhld	tocnt		; timeout
	inx	h
	shld	tocnt
	jmp	failure

recvchk:ora	a
	jnz	recvbad

        lhld	recvcnt         ; message is OK
	inx	h
	shld	recvcnt
	jmp	success

recvbad:lhld	chkcnt 		; bad checksum
	inx	h
	shld	chkcnt
	jmp	failure

        ;
	; wait for byte and read it - carry flag is set on timeout
        ;
recvbyte:
	lxi	h,RECVTMO

recvwait:
	in	UARTSTAT
	ani	DR
	jnz	readbyte
	dcx	h
	mov	a,h
	ora	l
	jnz	recvwait
	stc			; timeout
	ret

readbyte:
	in	UARTDATA
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

