;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; KP2-NIOS.ASM   [Kaypro 2X, should work with II/2/IV/4/10]
;;
;; To build KP2-NIOS.SPR:
;;   RMAC KP2-NIOS $PZ SZ
;;   LINK KP2-NIOS[OS]
;;
;; The Kaypro NIOS uses the 'J4 SERIAL DATA I/O' RS-232 port
;; to communicate with the file server. The default rate is
;; 19.2Kbps (max).
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	maclib	ndos

; Receive byte timeout counter
RECVTMO	equ	32768


BAUDPORT	equ     0       ; set 'J4 SERIAL DATA I/O' baud rate
  BAUD50        equ     00H
  BAUD75        equ     01H
  BAUD110       equ     02H
  BAUD134       equ     03H
  BAUD150       equ     04H
  BAUD300       equ     05H
  BAUD600       equ     06H
  BAUD1200      equ     07H
  BAUD1800      equ     08H
  BAUD2000      equ     09H
  BAUD2400      equ     0AH
  BAUD3600      equ     0BH
  BAUD4800      equ     0CH
  BAUD7200      equ     0DH
  BAUD9600      equ     0EH
  BAUD19200     equ     0FH 

DATAPORT	equ	4       ; read/write 'J4 SERIAL DATA I/O'

CMDPORT		equ	6       ; command/status on 'J4 SERIAL DATA I/O'
  REG0          equ     0
  REG1          equ     1
  REG2          equ     2
  REG3          equ     3
  REG4          equ     4
  REG5          equ     5
  REG6          equ     6
  REG7          equ     7
  NULLCODE      equ     0
  ABORT         equ     08h     ; SDLC
  RESET?INT     equ     10h
  CHAN?RESET    equ     18h
  ENB?INT       equ     20h
  RESET?TX      equ     28h
  ERROR?RESET   equ     30h
  RETURN?INT    equ     38h     ; channel A only
  RESET?RX?CRC  equ     40h
  RESET?TX?CRC  equ     80h
  RESET?TX?UND  equ     0c0h
  
  WR1?EXT?INT   equ     01h
  WR1?TX?INT    equ     02h
  WR1?STAT?VEC  equ     04h     ; status affects vector, channel B only
  WR1?RX?INTF   equ     08h     ; interrupt on first char
  WR1?RX?INTV   equ     10h     ; interrupt on all Rx chars, parity affects vector  
  WR1?RX?INTA   equ     18h     ; interrupt on all Rx chars, parity does not affect vector
  
  ; WR2 (channel B only) set interrupt vector
  
  WR3?RX?ENB    equ     01h     ; receive enable
  WR3?SYNC?INH  equ     02h     ; sync character load inhibit
  WR3?ADR?SRCH  equ     04h     ; address search mode (SDLC)
  WR3?RX?CRC    equ     08h     ; Rx CRC enable
  WR3?HUNT      equ     10h     ; Enter hunt phase
  WR3?AUTO      equ     20h     ; auto enables
  WR3?RX?BITS?5 equ     0
  WR3?RX?BITS?7 equ     40h
  WR3?RX?BITS?6 equ     80h
  WR3?RX?BITS?8 equ     0c0h
  
  WR4?ODD?PAR   equ     01h
  WR4?EVEN?PAR  equ     03h
  WR4?1?STOP    equ     04h     ; 1 stop bit
  WR4?15?STOP   equ     08h     ; 1.5 stop bits
  WR4?2?STOP    equ     0ch     ; 2 stop bits
  WR4?8?SYNC    equ     0
  WR4?16?SYNC   equ     10h
  WR4?SDLC      equ     20h
  WR4?SDLC?EXT  equ     30h
  WR4?X1?CLK    equ     0
  WR4?X16?CLK   equ     40h
  WR4?X32?CLK   equ     80h
  WR4?X64?CLK   equ     0c0h
  
  WR5?TX?CRC    equ     01h     ; transmit CRC enable
  WR5?RTS       equ     02h
  WR5?CRC16     equ     04h     ; CRC16 or SDLC polynomial select
  WR5?TX?ENB    equ     08h     ; transmit enable
  WR5?BREAK     equ     10h
  WR5?TX?BITS?5 equ     0
  WR5?TX?BITS?7 equ     20h
  WR5?TX?BITS?6 equ     40h
  WR5?TX?BITS?8 equ     60h
  WR5?DTR       equ     80h
  
  ; WR6 Sync bits
  ; WR7 Sync bits
  
  RD0?RX?CHAR   equ     01h     ; Rx char available
  RD0?INT       equ     02h
  RD0?TX?EMPTY  equ     04h     ; Tx buffer is ready for another char
  RD0?DCD       equ     08h
  RD0?SYNC      equ     10h
  RD0?CTS       equ     20h
  RD0?TX?UND    equ     40h
  RD0?BREAK     equ     80h
  
  RD1?ALL?SENT  equ     01h
  RD1?PAR?ERR   equ     10h     ; parity error
  RD1?RX?OVR    equ     20h
  RD1?FRM       equ     40h     ; framing error
  RD1?END?FRM   equ     80h     ; end of frame (SDLC)
  
  ; RD2 interrupt vector
  
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
init:	mvi	a,CHAN?RESET
	out     CMDPORT
	mvi	a,REG4
	out	CMDPORT
	mvi	a,WR4?X16?CLK OR WR4?1?STOP ; 44h
	out	CMDPORT
	mvi	a,REG1
	out	CMDPORT
	mvi	a,0             ; no interrupts
	out	CMDPORT
	mvi	a,REG3
	out	CMDPORT
	mvi	a,WR3?RX?BITS?8 OR WR3?RX?ENB ; 0c1h
	out	CMDPORT
	mvi	a,REG5
	out	CMDPORT
	mvi	a,WR5?TX?BITS?8 OR WR5?TX?ENB OR WR5?RTS ; 6ah
	out	CMDPORT

	mvi	a,BAUD19200 ; 0fh
	out	BAUDPORT	; 19.2 Kbps

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

txbusy:	in      CMDPORT
	ani	RD0?TX?EMPTY    ; 04h
	jz	txbusy
	ldax	d               ; get byte
	out	DATAPORT        ; send it
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
	in	CMDPORT
	ani	RD0?RX?CHAR
	jnz	readbyte
	dcx	h
	mov	a,h
	ora	l
	jnz	recvwait
	stc			; timeout
	ret

readbyte:
	in	DATAPORT
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

