;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NECHO.ASM
;;
;; NDOS Message echo
;;
;; On start, dma contains command line argument length byte
;; and command line.
;; Stack pointer should be within CCP.
;; Check for NDOS; display error if not running.
;; Copy command line arguments to buf and call NDOS to send it.
;; Call NDOS to receive response.
;; On a=0(success), print response.
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
	jz dousage
	mov c,a
loop:	inx h
	mov a,m
	stax d
	inx d
	dcr c
	jnz loop

	lda defdma
	adi 3		; include LEN, CMD, and CHK bytes
	sta msgbuf

loop1:
	mvi c,n?smsg
	lxi d,msgbuf
	call bdosv		; send message to server

	mvi c,n?rmsg
	lxi d,buffer
	call bdosv		; get response

	ora a
	jnz timeout

	; print response from server
	lda buffer		; get LEN byte
	dcr a			; subtract 1
	mov e,a
	mvi d,0
	lxi h,buffer
	dad d			; de is pointing to CHK byte
	mvi m,'$'		; terminate the string
	lxi d,buffer+2	; point to first byte of response (ECHO doesn't have a Status byte)
	mvi c,prnstr
	call bdosv		; print the response
	
	lxi d,crlf
	mvi c,prnstr
	call bdosv		; print CR, LF
    
	; loop if there's no keypress from the console
	mvi c,constat
	call bdosv
	ora a
	jz loop1        
	mvi c,conin
	call bdosv		; remove the keypress so it's not waiting for the CCP
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
        jmp quit

	; Print usage
dousage: mvi c, prnstr
	lxi d,usage
	call bdosv
	
quit:   lhld    savestack
        sphl                    ; sp = hl
        ret                     ; quit
     
nondoserr:
	db 'NDOS not loaded',cr,lf,'$'

toerr:	db 'Timeout',cr,lf,'$'

serr:	db 'Directory not found',cr,lf,'$'

usage:	db 'necho <text to send to server>'
crlf:	db cr,lf,'$'

;; NDOS request message
msgbuf: db 0		; LEN
	db NECHO	; CMD
	ds 148		; DATA and CHK

;; NDOS response buffer
buffer:	ds 150

savestack:
        dw 0
        
        ds 16
stack:	

        end start
