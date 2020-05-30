;
; Relocating CCP
;
; Move image at 0200h thru 09ffh to BDOS-0800h.
; Process fixup addresses in table.
; Jump to BDOS-0800h+3
;
warmv	equ 0000h
cdisk	equ 0004h
bdosv	equ 0005h

image	equ 0500h	; location of CCP in this file
imagesz	equ 0800h	; size of CCP
imgloc	equ 3300h	; assume CCP20.BIN
	
	org 0100h

	; get page address of BDOS
	lda bdosv+2
	sui imagesz/256
	sta destpage
	; a = destination page
	mvi b,imgloc/256
	; b = image original page
	sub b
	sta pgoffset
	; iterate offsets in fixuptbl and add offset
	lxi h,fixuptbl
	lxi b,(endfixup-fixuptbl)/2
fixuploop:
	mov e,m		; e = low-byte of fixup address offset
	inx h
	mov d,m		; d = high-byte of fixup address offset
	inx h
	push h		; save pointer into fixup table
	lxi h,image
	dad d		; add offset in de to hl; points to byte in image
	lda pgoffset
	add m		; read byte to adjust in image
	mov m,a		; write adjusted page value back to image 
	pop h		; restore pointer into fixup table
	dcx b
	mov a,b
	ora c	
	jnz fixuploop

	lda destpage
	mov d,a
	mvi e,0		; de = destination
	lxi h,image	; hl = source
	lxi b,imagesz	; bc = number of bytes to move
moveloop:
	mov a,m		; get byte at hl
	stax d		; write byte to de
	inx h		; ++hl
	inx d		; ++de
	dcx b		; --bc
	mov a,b
	ora c
	jnz moveloop

	lda cdisk
	mov c,a		; tell CCP which drive is default
	lda destpage
	mov h,a
	mvi l,3
	pchl		; jump to address in hl

destpage:
	db 0
pgoffset:
	db 0
fixuptbl:
	dw 0002h
	dw 0005h
	dw 0089h
	dw 0095h
	dw 009Ch
	dw 00A1h
	dw 00A6h
	dw 00AAh
	dw 00B3h
	dw 00B7h
	dw 00C8h
	dw 00CFh
	dw 00D3h
	dw 00D6h
	dw 00D9h
	dw 00DEh
	dw 00E3h
	dw 00E8h
	dw 00EBh
	dw 00EEh
	dw 00FDh
	dw 0100h
	dw 0103h
	dw 0108h
	dw 010Dh
	dw 011Ch
	dw 0123h
	dw 012Bh
	dw 013Bh
	dw 013Fh
	dw 0142h
	dw 0148h
	dw 014Bh
	dw 014Eh
	dw 0151h
	dw 0154h
	dw 0158h
	dw 015Bh
	dw 015Eh
	dw 0161h
	dw 0164h
	dw 016Ch
	dw 016Fh
	dw 0176h
	dw 0179h
	dw 017Ch
	dw 017Fh
	dw 0183h
	dw 0186h
	dw 0189h
	dw 018Ch
	dw 018Fh
	dw 0192h
	dw 0195h
	dw 0198h
	dw 019Bh
	dw 01A0h
	dw 01A6h
	dw 01A9h
	dw 01B0h
	dw 01B4h
	dw 01B9h
	dw 01BDh
	dw 01C0h
	dw 01DFh
	dw 01E8h
	dw 01EBh
	dw 01EEh
	dw 01F1h
	dw 01F4h
	dw 01F7h
	dw 01FAh
	dw 0201h
	dw 0207h
	dw 020Bh
	dw 020Eh
	dw 0214h
	dw 0218h
	dw 021Ch
	dw 0221h
	dw 0226h
	dw 0229h
	dw 022Ch
	dw 022Fh
	dw 0237h
	dw 0258h
	dw 0262h
	dw 0265h
	dw 026Bh
	dw 026Eh
	dw 0272h
	dw 0276h
	dw 027Dh
	dw 0287h
	dw 028Bh
	dw 028Fh
	dw 0293h
	dw 029Ah
	dw 029Dh
	dw 02A3h
	dw 02A8h
	dw 02AEh
	dw 02B1h
	dw 02B4h
	dw 02B8h
	dw 02BFh
	dw 02C6h
	dw 02CAh
	dw 02CDh
	dw 02D3h
	dw 02D8h
	dw 02DEh
	dw 02E1h
	dw 02E4h
	dw 02E8h
	dw 02EFh
	dw 02F8h
	dw 02FCh
	dw 0307h
	dw 030Ch
	dw 0330h
	dw 0339h
	dw 0340h
	dw 0346h
	dw 034Ch
	dw 0353h
	dw 0357h
	dw 035Bh
	dw 035Eh
	dw 036Ah
	dw 036Dh
	dw 0370h
	dw 0377h
	dw 037Ah
	dw 037Dh
	dw 0381h
	dw 0384h
	dw 0387h
	dw 038Ah
	dw 038Fh
	dw 0394h
	dw 0397h
	dw 039Dh
	dw 03A0h
	dw 03A3h
	dw 03A6h
	dw 03A9h
	dw 03ACh
	dw 03B0h
	dw 03B3h
	dw 03B6h
	dw 03C2h
	dw 03C4h
	dw 03C6h
	dw 03C8h
	dw 03CAh
	dw 03CCh
	dw 03CEh
	dw 03D4h
	dw 03D7h
	dw 03DBh
	dw 03DEh
	dw 03ECh
	dw 03EFh
	dw 03FAh
	dw 03FDh
	dw 0401h
	dw 0404h
	dw 040Dh
	dw 0415h
	dw 041Ch
	dw 0424h
	dw 0428h
	dw 042Ch
	dw 0431h
	dw 0438h
	dw 043Dh
	dw 0449h
	dw 0451h
	dw 0457h
	dw 045Ah
	dw 0460h
	dw 0465h
	dw 0468h
	dw 046Eh
	dw 0473h
	dw 0476h
	dw 0479h
	dw 047Ch
	dw 047Fh
	dw 0485h
	dw 048Eh
	dw 0494h
	dw 0497h
	dw 049Ah
	dw 049Dh
	dw 04A8h
	dw 04ACh
	dw 04B6h
	dw 04B9h
	dw 04BDh
	dw 04C3h
	dw 04C8h
	dw 04CBh
	dw 04CEh
	dw 04D3h
	dw 04D6h
	dw 04DCh
	dw 04E3h
	dw 04EAh
	dw 04EFh
	dw 04F6h
	dw 04FBh
	dw 0502h
	dw 0507h
	dw 050Ah
	dw 050Dh
	dw 0511h
	dw 0514h
	dw 0517h
	dw 051Ah
	dw 051Eh
	dw 0521h
	dw 0526h
	dw 0529h
	dw 052Ch
	dw 052Fh
	dw 0532h
	dw 0536h
	dw 053Dh
	dw 0541h
	dw 0544h
	dw 0547h
	dw 054Ah
	dw 054Eh
	dw 0551h
	dw 055Fh
	dw 0562h
	dw 0565h
	dw 0568h
	dw 056Bh
	dw 056Eh
	dw 0571h
	dw 0576h
	dw 057Ch
	dw 0580h
	dw 0584h
	dw 058Dh
	dw 0593h
	dw 0596h
	dw 0599h
	dw 059Ch
	dw 059Fh
	dw 05A3h
	dw 05A6h
	dw 05A9h
	dw 05ACh
	dw 05AFh
	dw 05B3h
	dw 05B6h
	dw 05B9h
	dw 05BCh
	dw 05C0h
	dw 05C4h
	dw 05C7h
	dw 05CBh
	dw 05D8h
	dw 05E2h
	dw 05E5h
	dw 05E8h
	dw 05EDh
	dw 05F0h
	dw 05F3h
	dw 05F6h
	dw 05FAh
	dw 05FDh
	dw 0600h
	dw 0603h
	dw 0606h
	dw 0612h
	dw 0615h
	dw 0618h
	dw 061Ch
	dw 061Fh
	dw 0622h
	dw 0625h
	dw 0628h
	dw 062Dh
	dw 0630h
	dw 0634h
	dw 0639h
	dw 063Eh
	dw 0643h
	dw 0646h
	dw 0649h
	dw 064Eh
	dw 0653h
	dw 0658h
	dw 065Dh
	dw 0660h
	dw 0663h
	dw 0666h
	dw 0669h
	dw 066Ch
	dw 066Fh
	dw 0672h
	dw 0675h
	dw 0678h
	dw 067Bh
	dw 067Eh
	dw 0681h
	dw 0690h
	dw 0695h
	dw 0699h
	dw 069Eh
	dw 06A1h
	dw 06A4h
	dw 06A7h
	dw 06AAh
	dw 06AFh
	dw 06B2h
	dw 06B6h
	dw 06BAh
	dw 06BDh
	dw 06C0h
	dw 06C3h
	dw 06C6h
	dw 06CCh
	dw 06D0h
	dw 06D4h
	dw 06D7h
	dw 06DAh
	dw 06DDh
	dw 06E5h
	dw 06E8h
	dw 06EBh
	dw 06EEh
	dw 06F6h
	dw 06FDh
	dw 0700h
	dw 0705h
	dw 0708h
	dw 070Bh
	dw 070Eh
	dw 0713h
	dw 0718h
	dw 071Dh
	dw 0721h
	dw 0727h
	dw 072Ch
	dw 072Fh
	dw 0734h
	dw 0739h
	dw 073Dh
	dw 0748h
	dw 074Eh
	dw 0755h
	dw 0758h
	dw 075Bh
	dw 0761h
	dw 0764h
	dw 0767h
	dw 076Ah
	dw 076Dh
	dw 0770h
	dw 0773h
	dw 0776h
	dw 0779h
	dw 0788h
	dw 078Bh
	dw 078Eh
	dw 0793h
	dw 0797h
	dw 079Ah
endfixup:
	end
