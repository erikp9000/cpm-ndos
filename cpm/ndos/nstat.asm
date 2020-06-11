;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NSTAT.ASM
;;
;; NDOS status
;;
;; On start, dma contains command line argument length byte
;; and command line.
;; Stack pointer should be within CCP.
;; Check for NDOS; display error if not running.
;; Print:
;;   BDOS vector       : xxxx
;;   BIOS vector       : xxxx
;;   Messages sent     : 0000
;;   Messages received : 0000
;;   Receive timeouts  : 0000
;;   Checksum errors   : 0000
;;
	maclib  ndos

	org     tpa

start:	lxi     h,0
        dad     sp              ; hl = sp
        shld    savestack       ; save original stack pointer
        lxi     sp,stack

	mvi c,n?ver
	call bdosv
	cpi 10h
	jc nondos

	; NDOS is present

	push psw
	lxi d,signon
	mvi c,prnstr
	call bdosv
	pop psw
	push psw
	rrc
	rrc
	rrc
	rrc
	call prnchar
	mvi e,'.'
	mvi c,conout
	call bdosv
	pop psw
	call prnchar
	call prncrlf

	lxi d,bdosvstr
	mvi c,prnstr
	call bdosv

	lhld bdosv+1
	call prnword
	call prncrlf

	lxi d,warmvstr
	mvi c,prnstr
	call bdosv

	lhld warmv+1
	call prnword
	call prncrlf

	mvi c,n?stats
	call bdosv
	; HL is pointing to the NDOS message counters

	mvi c,4
	lxi d,0
loop:	push b
	call prnstx	; print string at index de
	push d		; save de
	mov e,m
	inx h
	mov d,m
	inx h
	push h		; save next address
	xchg		; get value into hl
	call prnword
	call prncrlf
	pop h		; pop next address back into hl
	pop d		; restore string index
	inx d
	pop b		; restore counter
	dcr c
	jnz loop

        jmp quit

        

	; NDOS not found
	
nondos:	mvi c,prnstr
	lxi d,nondoserr
	call bdosv

	lxi d,bdosvstr
	mvi c,prnstr
	call bdosv

	lhld bdosv+1
	call prnword
	call prncrlf

	lxi d,warmvstr
	mvi c,prnstr
	call bdosv

	lhld warmv+1
	call prnword
	call prncrlf

        jmp quit


	; Timeout contacting server
timeout:mvi c,prnstr
	lxi d,toerr
	call bdosv
        jmp quit
        
	; Error status from server
serverr:mvi c,prnstr
	lxi d,serr
	call bdosv

quit:   lhld    savestack
        sphl                    ; sp = hl
        ret                     ; quit
        
; Print CR & LF
prncrlf:
	lxi d,crlf
	mvi c,prnstr
	jmp bdosv


; Print string from string table at index de
prnstx:	push h
	push d
	lxi h,strtbl
	dad d
	dad d
	mov e,m
	inx h
	mov d,m
	mvi c,prnstr
	call bdosv
	pop d
	pop h
	ret

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

signon:	db 'NDOS $'

strtbl:	dw msgssent
	dw msgsrecv
	dw msgsto
	dw msgschk

bdosvstr:db 'BDOS vector   : $'
warmvstr:db 'BIOS vector   : $'
msgssent:db 'Messages sent : $'
msgsrecv:db 'Messages recv : $'
msgsto:  db 'Timeouts      : $'
msgschk: db 'Checksum errs : $'

nondoserr:
	db 'NDOS not loaded',cr,lf,'$'

toerr:	db 'Timeout',cr,lf,'$'

serr:	db 'Error',cr,lf,'$'

savestack:
        dw 0
        
        ds 16
stack:	

	end

