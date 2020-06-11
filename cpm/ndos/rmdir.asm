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

	; copy command line args from dmabuf
	lxi d,msgbuf+2	; point to start of data
	lxi h,defdma	; command-line
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

docwd:	lda defdma
	adi 3		; include LEN, CMD, and CHK bytes
	sta msgbuf
	
	mvi c,n?smsg
	lxi d,msgbuf
	call bdosv

	mvi c,n?rmsg
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
	call bdosv
        jmp quit
        

	; NDOS not found
	
nondos:	mvi c,prnstr
	lxi d,nondoserr
	call bdosv
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
        
        
nondoserr:
	db 'NDOS not loaded',cr,lf,'$'

toerr:	db 'Timeout',cr,lf,'$'

serr:	db 'Directory not found',cr,lf,'$'

;; NDOS request message
msgbuf: db 0		; LEN
	db NRMDIR	; CMD
	ds 148		; DATA and CHK

;; NDOS response buffer
buffer:	ds 150

savestack:
        dw 0
        
        ds 16
stack:	

        end start

