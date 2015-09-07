IDEAL
P8086
Model Tiny

LOCALS @@

DEMOAPI EQU     0F8h

PUBLIC enablemus
PUBLIC disablemus
PUBLIC vintsetup
PUBLIC vintteardown
EXTRN MusicData

SEGMENT CODE para public
ASSUME  cs:CODE, ds:CODE, es:CODE

org 100h
start:
	; Write message
	mov dx, offset message
	mov ah, 9
	int 21h
	
	mov [word musicbuf], offset MusicData
	mov [word musicbuf+2], cs
	mov [musicidx], 0

    mov [mloopstart], 0
    mov [mloopend], 22172
	
	call vintsetup
	call enablemus

@@waitKey:
	; Wait for keypress
	mov ah, 1
	int 16h
	jz @@waitKey
	
	call vintteardown
	call disablemus
	
	ret

message db	'HAPYBEEP.MON - Triace/DESiRE',0Dh,0Ah
		db	'Press any key to exit',0Dh,0Ah,'$'
		
SYSTEMFRIENDLY equ 0

;The Mode/Command register at I/O address 43h is defined as follows:
;
;       7 6 5 4 3 2 1 0
;       * * . . . . . .  Select chan:   0 0 = Channel 0
;                                       0 1 = Channel 1
;                                       1 0 = Channel 2
;                                       1 1 = Read-back command (8254 only)
;                                             (Illegal on 8253, PS/2)
;       . . * * . . . .  Cmd/Acc mode:  0 0 = Latch count value command
;                                       0 1 = Access mode: lobyte only
;                                       1 0 = Access mode: hibyte only
;                                       1 1 = Access mode: lobyte/hibyte
;       . . . . * * * .  Oper. mode:  0 0 0 = Mode 0
;                                     0 0 1 = Mode 1
;                                     0 1 0 = Mode 2
;                                     0 1 1 = Mode 3
;                                     1 0 0 = Mode 4
;                                     1 0 1 = Mode 5
;                                     1 1 0 = Mode 2
;                                     1 1 1 = Mode 3
;       . . . . . . . *  BCD/Binary mode: 0 = 16-bit binary
;                                         1 = four-digit BCD
;
; PC and XT : I/O address 61h, "PPI Port B", read/write
;       7 6 5 4 3 2 1 0
;       * * * * * * . .  Not relevant to speaker - do not modify!
;       . . . . . . * .  Speaker Data
;       . . . . . . . *  Timer 2 Gate


CHAN0           EQU      00000000b
CHAN1           EQU      01000000b
CHAN2           EQU      10000000b
AMREAD          EQU      00000000b
AMLOBYTE        EQU      00010000b
AMHIBYTE        EQU      00100000b
AMBOTH          EQU      00110000b
MODE0           EQU      00000000b
MODE1           EQU      00000010b
MODE2           EQU      00000100b
MODE3           EQU      00000110b
MODE4           EQU      00001000b
MODE5           EQU      00001010b
BINARY          EQU      00000000b
BCD             EQU      00000001b

CTCMODECMDREG   EQU      043h
CHAN0PORT       EQU      040h
CHAN2PORT       EQU      042h
;CGAPITDIVRATE  EQU      19912          ;(912*262) div 12
CGAPITDIVRATE   EQU      (912*262) / 12 ;19912
PPIPORTB        EQU      61h

PROC    PlayerINT       FAR
; Update music
; (When we can guarantee that music will be paragraph-aligned, we can
; optimize this; until then, we have to maintain an index)
		push    ax
		push	bx

        push    si
        push    dx
        mov     bx,[musicidx]           ;load current music index
        inc     bx
        inc     bx                      ;advance to next music datum
        cmp     bx,[mloopend]           ;index past loop end?
        jbe     mcontinue               ;adjust if so, fall through if not
        mov     bx,[mloopstart]         ;Adjust music pointer to loop start
		
mcontinue:
        mov     [musicidx],bx           ;store current or updated index
		push	ds
        lds     si,[musicbuf]           ;ds:bx now points to music buffer
        mov     ax,[bx+si]              ;grab indexed value to send to PIT2
        mov     dx,CHAN2PORT            ;channel 2 should be gated to speaker
        out     dx,al                   ;output lobyte
        mov     al,ah
        out     dx,al                   ;output hibyte
		pop		ds
		
        pop     dx
        pop     si
		
		pop		bx

        mov     al,20h                  ;acknowledge PIC so others may fire
        out     20h,al                  ;ok to do this here since we are
        pop     ax                      ;top priority in PIC chain

		iret
ENDP
		
PROC vintsetup
		cli

; Save old INT08 vector
        push    ds
        xor     bx,bx
        mov     ds,bx
        mov     bx,[20h]
        mov     [word cs:oldint08],bx
        mov     bx,[22h]
        mov     [word cs:oldint08+2],bx
        pop     ds

@@setPIT:
; Set new firing rate
        mov     al,CHAN0 + AMBOTH + MODE2 + BINARY
        out     CTCMODECMDREG,al
        mov     ax,CGAPITDIVRATE
        out     CHAN0PORT,al            ;output lobyte first
        out     04fh,al                 ;allow device recovery time
        mov     al,ah
        out     CHAN0PORT,al

; Set housekeeping hook as default
vinthookhouse:
        push    ds
        xor     bx,bx
        mov     ds,bx
        mov     [word 20h],offset PlayerINT
        mov     [22h],cs                ;20h = 32d = (int08 * 4)
        pop     ds
		sti

        ret
ENDP

PROC vintteardown
; Restore original firing rate
		cli

        mov     al,CHAN0 + AMBOTH + MODE2 + BINARY
        out     CTCMODECMDREG,al
        xor     ax,ax                   ;xtal / 65536 iterations = 18.2Hz
        out     CHAN0PORT,al
        out     CHAN0PORT,al
; Restore old INT08 vector
        push    ds
        xor     bx,bx
        mov     ds,bx
        mov     bx,[word cs:oldint08]
        mov     [20h],bx
        mov     bx,[word cs:oldint08+2]
        mov     [22h],bx
        pop     ds
		sti

		ret
ENDP
		
PROC enablemus
; Enable speaker and tie input pin to CTC Chan 2 by setting bits 1 and 0
        push    ax
        in      al,PPIPORTB             ;read existing port bits
        or      al,3                    ;turn on speaker gating
        out     PPIPORTB,al             ;set port
        pop     ax
        ret
ENDP

PROC disablemus
; Disable speaker by clearing bits 1 and 0
        push    ax
        in      al,PPIPORTB
        and     al,not 3
        out     PPIPORTB,al
        pop     ax
        ret
ENDP

; Handler data area

ALIGN 16 ;does what we expect?  No... will investigate later.

STRUC HandlerDataStruc
musicidx        dw ?
mloopstart      dw ?
mloopend        dw ?
musicbuf        dd ?
oldint08        dd ?
IF SYSTEMFRIENDLY
chan0counter    dw ?
ENDIF
ENDS HandlerDataStruc

handlerdata:
musicidx        dw 0
mloopstart      dw 0
mloopend        dw 0
musicbuf        dd 0
oldint08        dd 0
IF SYSTEMFRIENDLY
chan0counter    dw 0
ENDIF

ENDS CODE
	
END start

