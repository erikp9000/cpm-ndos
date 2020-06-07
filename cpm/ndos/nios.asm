;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NIOS.ASM       [stub]
;;
;; To build NIOS.SPR:
;;   RMAC NIOS $PZ SZ
;;   LINK NIOS[OS]
;;
;; The NIOS implements the hardware-specific functions
;; required to communicate with the ndos-srv. This is 
;; the default NIOS loaded by the LDNDOS loader. It can
;; be used to test loading/unloading of NDOS on the target
;; system before developing NIOS.
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

	maclib	ndos

        ;
	; Jump table used by NDOS to access network functions
        ; (Don't put anything before these or NDOS will be broken.)
        ;
	jmp init
	jmp smsg
	jmp rmsg
	jmp nstat

        ; return success/failure code
        
success:lxi	h,0
	mov	a,l
	ret

failure:lxi	h,0ffh
	mov	a,l
	ret
        
	; network statistics counters

sentcnt:dw 0		; count of messages sent
recvcnt:dw 0		; count of messages received
tocnt:	dw 0	        ; count of timed-out messages
chkcnt:	dw 0		; count of messages with bad checksum

	;
	; Initialize the network
	;
	; Inputs:
	;     None
	; Outputs:
	;     a = 0(success)/FF(failure)
	;
init:   jmp     failure


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
smsg:   jmp     failure


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
rmsg:   jmp     failure


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

