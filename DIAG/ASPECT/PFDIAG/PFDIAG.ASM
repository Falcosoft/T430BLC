; PFDIAG.ASM
; Read-only Ivy Bridge panel-fitter MMIO diagnostic for ThinkPad T430.
;
; Uses the exact safe protected-mode framework proven by BLCSET/FITREAD.
;
; Build:
;   TASM /m9 PFDIAG.ASM
;   TLINK /t PFDIAG.OBJ
;
; Run without EMM386:
;   PFDIAG
;
; No MMIO writes are performed.

.model tiny
.386p
.code
org 100h

include T430LCD.INC

start:
        mov ax,cs
        mov ds,ax
        mov es,ax

        mov dx,offset MsgTitle
        call PrintZ

        ; Intel graphics BAR0 via PCI BIOS, bus 0/device 2/function 0, offset 10h.
        mov di,10h
        call PciReadDword
        jc PciFail
        mov eax,ecx
        and eax,0FFFFFFF0h
        mov dword ptr [MmioBase],eax
        test eax,eax
        jz BarFail

        mov dx,offset MsgBar
        call PrintZ
        call PrintHex32
        call PrintCRLF

        ; XMS/A20.
        mov ax,4300h
        int 2Fh
        cmp al,80h
        jne NoXms
        mov ax,4310h
        int 2Fh
        mov word ptr [XmsEntry],bx
        mov word ptr [XmsEntry+2],es
        push ds
        pop es
        mov ah,05h
        call dword ptr cs:[XmsEntry]
        or ax,ax
        jz A20Fail
        mov byte ptr [A20EnabledByUs],1

        call PrepareProtectedMode

        mov dx,offset MsgEnter
        call PrintZ

        pushf
        pop word ptr [SavedFlags]
        cli
        in al,70h
        mov byte ptr [SavedPort70],al
        or al,80h
        out 70h,al

        lgdt fword ptr [Gdtr]
        mov eax,cr0
        or al,1
        mov cr0,eax

        db 0EAh
        dw offset ProtectedEntry
        dw SEL_CODE16

ProtectedEntry:
        mov ax,SEL_DATA16
        mov ss,ax
        mov es,ax
        mov ax,SEL_FLAT
        mov ds,ax

        mov byte ptr es:[Checkpoint],1

        ; Legacy/global panel fitter registers.
        mov esi,dword ptr es:[MmioBase]
        add esi,61230h
        MMIO_READ_EAX_ESI
        mov dword ptr es:[LegacyCtl],eax
        add esi,4
        MMIO_READ_EAX_ESI
        mov dword ptr es:[LegacyRatios],eax
        add esi,4
        MMIO_READ_EAX_ESI
        mov dword ptr es:[LegacyAuto],eax

        mov byte ptr es:[Checkpoint],2

        ; Fitter A.
        mov esi,dword ptr es:[MmioBase]
        add esi,68070h
        MMIO_READ_EAX_ESI
        mov dword ptr es:[A_Pos],eax
        add esi,4
        MMIO_READ_EAX_ESI
        mov dword ptr es:[A_Size],eax
        add esi,0Ch
        MMIO_READ_EAX_ESI
        mov dword ptr es:[A_Ctl],eax
        add esi,4
        MMIO_READ_EAX_ESI
        mov dword ptr es:[A_VScale],eax
        add esi,0Ch
        MMIO_READ_EAX_ESI
        mov dword ptr es:[A_HScale],eax

        mov byte ptr es:[Checkpoint],3

        ; Fitter B.
        mov esi,dword ptr es:[MmioBase]
        add esi,68870h
        MMIO_READ_EAX_ESI
        mov dword ptr es:[B_Pos],eax
        add esi,4
        MMIO_READ_EAX_ESI
        mov dword ptr es:[B_Size],eax
        add esi,0Ch
        MMIO_READ_EAX_ESI
        mov dword ptr es:[B_Ctl],eax
        add esi,4
        MMIO_READ_EAX_ESI
        mov dword ptr es:[B_VScale],eax
        add esi,0Ch
        MMIO_READ_EAX_ESI
        mov dword ptr es:[B_HScale],eax

        mov byte ptr es:[Checkpoint],4

        ; Fitter C (same 800h pipe stride).
        mov esi,dword ptr es:[MmioBase]
        add esi,69070h
        MMIO_READ_EAX_ESI
        mov dword ptr es:[C_Pos],eax
        add esi,4
        MMIO_READ_EAX_ESI
        mov dword ptr es:[C_Size],eax
        add esi,0Ch
        MMIO_READ_EAX_ESI
        mov dword ptr es:[C_Ctl],eax
        add esi,4
        MMIO_READ_EAX_ESI
        mov dword ptr es:[C_VScale],eax
        add esi,0Ch
        MMIO_READ_EAX_ESI
        mov dword ptr es:[C_HScale],eax

        mov byte ptr es:[Checkpoint],5

        ; Return to real mode.
        mov ax,SEL_DATA16
        mov ds,ax
        mov es,ax
        mov ss,ax
        mov eax,cr0
        and al,0FEh
        mov cr0,eax
        db 0EAh
        dw offset RealModeReturn
        dw 0000h
ReturnSegment equ ($-2)

RealModeReturn:
        mov ax,cs
        mov ds,ax
        mov es,ax
        mov ss,ax
        mov al,byte ptr [SavedPort70]
        out 70h,al
        push word ptr [SavedFlags]
        popf

        mov dx,offset MsgReturned
        call PrintZ
        mov dx,offset MsgCheckpoint
        call PrintZ
        mov al,byte ptr [Checkpoint]
        call PrintHex8
        call PrintCRLF

        mov dx,offset MsgLegacy
        call PrintZ
        mov eax,dword ptr [LegacyCtl]
        call PrintHex32
        mov dx,offset MsgSlash
        call PrintZ
        mov eax,dword ptr [LegacyRatios]
        call PrintHex32
        mov dx,offset MsgSlash
        call PrintZ
        mov eax,dword ptr [LegacyAuto]
        call PrintHex32
        call PrintCRLF

        mov si,offset A_Ctl
        mov dx,offset MsgA
        call PrintFitter
        mov si,offset B_Ctl
        mov dx,offset MsgB
        call PrintFitter
        mov si,offset C_Ctl
        mov dx,offset MsgC
        call PrintFitter

        call DisableA20IfNeeded
        mov ax,4C00h
        int 21h

; SI points to CTL,VSCALE,HSCALE,POS,SIZE storage order is custom below.
PrintFitter proc near
        call PrintZ
        mov eax,dword ptr [si]
        call PrintHex32
        mov dx,offset MsgPos
        call PrintZ
        mov eax,dword ptr [si+12]
        call PrintHex32
        mov dx,offset MsgSize
        call PrintZ
        mov eax,dword ptr [si+16]
        call PrintHex32
        mov dx,offset MsgV
        call PrintZ
        mov eax,dword ptr [si+4]
        call PrintHex32
        mov dx,offset MsgH
        call PrintZ
        mov eax,dword ptr [si+8]
        call PrintHex32
        call PrintCRLF
        ret
PrintFitter endp

PrepareProtectedMode proc near
        push ax
        push bx
        push dx
        push eax
        xor eax,eax
        mov ax,cs
        shl eax,4
        mov bx,offset GdtCode16
        call SetDescriptorBase
        mov bx,offset GdtData16
        call SetDescriptorBase
        mov edx,eax
        xor eax,eax
        mov ax,offset GdtStart
        add eax,edx
        mov dword ptr [Gdtr+2],eax
        mov ax,cs
        mov word ptr cs:[ReturnSegment],ax
        pop eax
        pop dx
        pop bx
        pop ax
        ret
PrepareProtectedMode endp

SetDescriptorBase proc near
        mov word ptr [bx+2],ax
        ror eax,16
        mov byte ptr [bx+4],al
        mov byte ptr [bx+7],ah
        ror eax,16
        ret
SetDescriptorBase endp

DisableA20IfNeeded proc near
        cmp byte ptr [A20EnabledByUs],0
        je A20Done
        mov ah,06h
        call dword ptr cs:[XmsEntry]
        mov byte ptr [A20EnabledByUs],0
A20Done:
        ret
DisableA20IfNeeded endp

PciReadDword proc near
        mov ax,0B10Ah
        xor bh,bh
        mov bl,10h
        int 1Ah
        ret
PciReadDword endp

PciFail:
        mov dx,offset MsgPciFail
        call PrintZ
        jmp ExitError
BarFail:
        mov dx,offset MsgBarFail
        call PrintZ
        jmp ExitError
NoXms:
        mov dx,offset MsgNoXms
        call PrintZ
        jmp ExitError
A20Fail:
        mov dx,offset MsgA20Fail
        call PrintZ
ExitError:
        call DisableA20IfNeeded
        mov ax,4C01h
        int 21h

PrintCRLF proc near
        mov dx,offset MsgCRLF
        call PrintZ
        ret
PrintCRLF endp

PrintZ proc near
        push ax
        push si
        mov si,dx
PZLoop:
        lodsb
        or al,al
        jz PZDone
        mov dl,al
        call PutCh
        jmp PZLoop
PZDone:
        pop si
        pop ax
        ret
PrintZ endp

PutCh proc near
        push ax
        mov ah,02h
        int 21h
        pop ax
        ret
PutCh endp

PrintHex32 proc near
        push eax
        ror eax,16
        call PrintHex16
        ror eax,16
        call PrintHex16
        pop eax
        ret
PrintHex32 endp
PrintHex16 proc near
        push ax
        mov al,ah
        call PrintHex8
        pop ax
        call PrintHex8
        ret
PrintHex16 endp
PrintHex8 proc near
        push ax
        push bx
        mov bl,al
        mov al,bl
        shr al,4
        call PrintNibble
        mov al,bl
        and al,0Fh
        call PrintNibble
        pop bx
        pop ax
        ret
PrintHex8 endp
PrintNibble proc near
        and al,0Fh
        cmp al,9
        jbe NibbleDigit
        add al,'A'-10
        jmp short NibbleOut
NibbleDigit:
        add al,'0'
NibbleOut:
        mov dl,al
        call PutCh
        ret
PrintNibble endp

GdtStart:
        dq 0
GdtCode16:
        dw 0FFFFh,0000h
        db 00h,09Ah,00h,00h
GdtData16:
        dw 0FFFFh,0000h
        db 00h,092h,00h,00h
GdtFlat:
        dw 0FFFFh,0000h
        db 00h,092h,0CFh,00h
GdtEnd:
Gdtr:
        dw GdtEnd-GdtStart-1
        dd 0

MmioBase dd 0
LegacyCtl dd 0
LegacyRatios dd 0
LegacyAuto dd 0

; Keep each fitter block in CTL, VSCALE, HSCALE, POS, SIZE order.
A_Ctl dd 0
A_VScale dd 0
A_HScale dd 0
A_Pos dd 0
A_Size dd 0
B_Ctl dd 0
B_VScale dd 0
B_HScale dd 0
B_Pos dd 0
B_Size dd 0
C_Ctl dd 0
C_VScale dd 0
C_HScale dd 0
C_Pos dd 0
C_Size dd 0

XmsEntry dd 0
SavedFlags dw 0
SavedPort70 db 0
A20EnabledByUs db 0
Checkpoint db 0

MsgTitle db 13,10,'PFDIAG - T430 Ivy Bridge panel-fitter MMIO diagnostic',13,10
         db 'READ-ONLY: no graphics MMIO writes.',13,10,0
MsgBar db 'Graphics MMIO BAR0: ',0
MsgEnter db 'Entering protected mode...',13,10,0
MsgReturned db 'Returned from protected mode.',13,10,0
MsgCheckpoint db 'Final checkpoint: ',0
MsgLegacy db 'Legacy 61230/61234/61238: ',0
MsgSlash db ' / ',0
MsgA db 'Fitter A CTL=',0
MsgB db 'Fitter B CTL=',0
MsgC db 'Fitter C CTL=',0
MsgPos db ' POS=',0
MsgSize db ' SIZE=',0
MsgV db ' VSCALE=',0
MsgH db ' HSCALE=',0
MsgPciFail db 'PCI BIOS BAR0 read failed.',13,10,0
MsgBarFail db 'Graphics BAR0 is zero.',13,10,0
MsgNoXms db 'HIMEM/XMS is unavailable.',13,10,0
MsgA20Fail db 'XMS could not enable A20.',13,10,0
MsgCRLF db 13,10,0

end start
