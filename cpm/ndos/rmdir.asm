;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; RMDIR.ASM
;;
;; NDOS Remove directory
;;
;; On start, dma contains command line argument length byte
;; and command line.
;; Stack pointer should be within CCP.
;; Check for NDOS; display error if not running.
;; Copy command line arguments to buf and call NDOS to send it.
;; Call NDOS to receive response.
;; On a=0(success), print new current working directory in response buf.
;; On a=0FFh(failure), print error.
;;

warmv	equ 0000h
cdisk	equ 0004h
bdosv	equ 0005h
dmabuf	equ 0080h
tpa	equ 0100h

cr	equ 0dh
lf	equ 0ah

;; BDOS function codes
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
ndosver	equ 40h
sendmsg	equ 41h
recvmsg	equ 42h

; NDOS CMD codes 
nfndfst	equ 002h
nfndnxt	equ 004h
nopen	equ 006h
nclose	equ 008h
ndelet	equ 00ah
nread	equ 00ch
nwrite	equ 00eh
ncreat	equ 010h
nrenam	equ 012h
ncwd	equ 020h
nmkdir	equ 022h
nrmdir	equ 024h
necho	equ 030h

	org 0100h

start:	
;	lxi h,stack
;	sphl

	mvi c,ndosver
	call bdosv
	cpi 10h
	jc nondos

	; NDOS is present

	; copy command line args from dmabuf
	lxi d,msgbuf+2	; point to start of data
	lxi h,dmabuf	; command-line
	mov a,m		; command-line length
	ora a
	jz docwd
	mov c,a
loop:	inx h
	mov a,m
	stax d
	inx d
	dcr c
	jnz loop

docwd:	lda dmabuf
	adi 3		; include LEN, CMD, and CHK bytes
	sta msgbuf
	
	mvi c,sendmsg
	lxi d,msgbuf
	call bdosv

	mvi c,recvmsg
	lxi d,buffer
	call bdosv

	ora a
	jnz timeout

	; check response code from server
	;lda buffer+2
	;ora a
	;jnz serverr

	; print response from server
	lda buffer
	dcr a
	mov e,a
	mvi d,0
	lxi h,buffer
	dad d
	mvi m,'$'
	lxi d,buffer+3
	mvi c,prnstr
	jmp bdosv
        

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

nondoserr:
	db 'NDOS not loaded',cr,lf,'$'

toerr:	db 'Timeout',cr,lf,'$'

serr:	db 'Directory not found',cr,lf,'$'

;; NDOS request message
msgbuf: db 0		; LEN
	db nrmdir	; CMD
	ds 148		; DATA and CHK

;; NDOS response buffer
buffer:	ds 150

;stack:	ds 256

        end start

