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

warmv	equ 0000h
cdisk	equ 0004h
bdosv	equ 0005h
dmabuf	equ 0080h
tpa	equ 0100h

cr	equ 0dh
lf	equ 0ah

;; BDOS function codes
conout	equ 2
prnstr	equ 9
openf	equ 0fh
closef	equ 10h
fndfst	equ 11h
fndnxt	equ 12h
readf	equ 14h
writef	equ 15h
creatf	equ 16h
setdma	equ 1ah

; NDOS function codes
ndosver	equ 40h   ; returns NDOS version in A
sendmsg	equ 41h   ; send buffer DE
recvmsg	equ 42h   ; recieve to buffer DE
stats	equ 43h   ; return HL pointing to status values

; NDOS CMD codes 
;nfndfst	equ 002h
;nfndnxt	equ 004h
;nopen	equ 006h
;nclose	equ 008h
;ndelet	equ 00ah
;nread	equ 00ch
;nwrite	equ 00eh
;ncreat	equ 010h
;nrenam	equ 012h
;ncwd	equ 020h
;nmkdir	equ 022h
;nrmdir	equ 024h
;necho	equ 030h

	org 0100h

start:	
;	lxi h,stack
;	sphl

	mvi c,ndosver
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

	mvi c,stats
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

	ret
        

	; NDOS not found
	
nondos:	mvi c,prnstr
	lxi d,nondoserr
	jmp bdosv

	; Timeout contacting server
timeout:mvi c,prnstr
	lxi d,toerr
	jmp bdosv

	; Error status from server
serverr:mvi c,prnstr
	lxi d,serr
	jmp bdosv


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

	end

