;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;
;; NSH.ASM
;;
;; NDOS Remote shell
;;
;; On start, dma contains command line argument length byte
;; and command line.
;; Stack pointer should be within CCP.
;; Check for NDOS; display error if not running.
;; Copy command line arguments to buf and call NDOS to send it.
;; Call NDOS to receive stdout.
;; On a=0FFh(failure), print error and quit.
;; On a=0(success), print response and loop checking for keyboard
;;   input to send and stdout responses to print.
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
        
        ; The Kaypro BIOS won't disable the drive motor unless we
        ; make a blocking call for console input.
        call dousage
        lxi h,retn              ; return from BIOS
        push h                  ; push return addr on stack
        lhld 1                  ; BIOS WBOOT
        lxi d,2*3
        dad d                   ; BIOS CONIN        
        pchl

	; copy command line args from dmabuf
retn:   lxi d,msgbuf+3	; point to start of data
	lxi h,defdma	; command-line
	mov a,m		; command-line length
	;;ora a
	;;jz dousage
	mov c,a
loop:	inx h
	mov a,m
	stax d
	inx d
	dcr c
	jnz loop

	lda defdma
	adi 1+3		; include buffer type, LEN, CMD, and CHK bytes
	sta msgbuf

loop1:
	mvi c,n?smsg
	lxi d,msgbuf
	call bdosv		; send message to server

        ; change msgbuf to a poll
        mvi a,1+3
        sta msgbuf              ; LEN of poll
        mvi a,1                 ; 1=poll for stdout
        sta msgbuf+2            ; buffer type
        
	mvi c,n?rmsg
	lxi d,buffer
	call bdosv		; get response

        ; check for timeout
	ora a
	jnz timeout

        ; check for no data (0)
        lda buffer+2            ; status
        ora a
        jz loop2
        
        ; check for quit (0xFF)
        inr a
        jz quit

        ; print response from server
	lda buffer		; get LEN byte
	sui 4			; a = a - 4
        lxi h,buffer+3          ; point to first byte of response
        
loop3:
        mvi c,dircon
        mov e,m
        push h
        push psw                ; a and flags
        call bdosv              ; output character
        pop psw
        pop h
        inx h
        dcr a
        jnz loop3
        
loop2:
	; check for keypress from the console
        mvi c,dircon
        mvi e,0ffh              ; check for input
        call bdosv
	ora a
	jz loop1                ; poll server
        
        ; get keypress from the console and send to server
        sta msgbuf+3            ; store stdin byte
        mvi a,2+3
        sta msgbuf              ; LEN
        
        ; loop...
        jmp loop1               ; send char and poll server
	
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
	jmp bdosv
	
quit:   lhld    savestack
        sphl                    ; sp = hl
        ret                     ; quit
     
nondoserr:
	db 'NDOS not loaded',cr,lf,'$'

toerr:	db 'Timeout',cr,lf,'$'

serr:	db 'Directory not found',cr,lf,'$'

usage:	db 'Press ENTER when drive motors stop $'
crlf:	db cr,lf,'$'

;; NDOS request message
msgbuf: db 0		; LEN
	db NSHELL	; CMD
        db 0            ; buffer type, 0=launch shell command, 1=stdin bytes
	ds 147		; buffer, DATA and CHK

;; NDOS response buffer
buffer:	db 0            ; LEN
        db 0            ; CMD
        db 0            ; status, 0=no stdout data, 1=stdout data, 0xFF=exited
        ds 147          ; stdout, DATA and CHK

savestack:
        dw 0
        
        ds 16
stack:	

        end start
