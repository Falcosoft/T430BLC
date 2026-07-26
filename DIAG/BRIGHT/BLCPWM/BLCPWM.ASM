; BLCPWM.ASM
; ThinkPad T430 / Ivy Bridge Intel HD Graphics 4000
; Read-only LCD backlight PWM register diagnostic.
;
; Build:
;   TASM /m9 BLCPWM.ASM
;   TLINK /t BLCPWM.OBJ
;
; Reads PCI BAR0 dynamically and samples:
;   BAR0 + 048250h  BLC_PWM_CPU_CTL2
;   BAR0 + 048254h  BLC_PWM_CPU_CTL
;   BAR0 + 061250h  BLC_PWM_CTL2
;   BAR0 + 061254h  BLC_PWM_CTL
;   BAR0 + 0C8250h  BLC_PWM_PCH_CTL1
;   BAR0 + 0C8254h  BLC_PWM_PCH_CTL2
;
; No MMIO or PCI writes are performed.

.model tiny
.386p
.code
org 100h

SEL_CODE16 equ 08h
SEL_DATA16 equ 10h
SEL_FLAT   equ 18h

start:
        mov     ax, cs
        mov     ds, ax
        mov     es, ax

        mov     dx, offset MsgTitle
        call    PrintZ

        ; Read graphics MMIO BAR0 from PCI 00:02.0 offset 10h.
        mov     di, 10h
        call    PciReadDword
        jc      PciReadFailed

        mov     eax, ecx
        and     eax, 0FFFFFFF0h
        mov     dword ptr [MmioBase], eax

        mov     dx, offset MsgBar0
        call    PrintZ
        call    PrintHex32
        call    PrintCRLF

        test    eax, eax
        jz      BarInvalid

        ; Read PCI config DWORD F4h as an extra read-only clue.
        mov     di, 0F4h
        call    PciReadDword
        jc      PciReadFailed
        mov     dword ptr [PciF4], ecx

        mov     dx, offset MsgPciF4
        call    PrintZ
        mov     eax, dword ptr [PciF4]
        call    PrintHex32
        call    PrintCRLF

        ; XMS is used only to enable A20.
        mov     ax, 4300h
        int     2Fh
        cmp     al, 80h
        jne     XmsNotPresent

        mov     ax, 4310h
        int     2Fh
        mov     word ptr [XmsEntry], bx
        mov     word ptr [XmsEntry+2], es

        push    ds
        pop     es

        mov     ah, 05h
        call    dword ptr cs:[XmsEntry]
        or      ax, ax
        jz      A20EnableFailed
        mov     byte ptr [A20EnabledByUs], 1

        call    PrepareProtectedMode

        mov     dx, offset MsgRead
        call    PrintZ

        pushf
        pop     word ptr [SavedFlags]
        cli

        in      al, 70h
        mov     byte ptr [SavedPort70], al
        or      al, 80h
        out     70h, al

        lgdt    fword ptr [Gdtr]

        mov     eax, cr0
        or      al, 01h
        mov     cr0, eax

        db      0EAh
        dw      offset ProtectedEntry
        dw      SEL_CODE16

ProtectedEntry:
        mov     ax, SEL_DATA16
        mov     ss, ax

        mov     ax, SEL_FLAT
        mov     ds, ax
        mov     es, ax

        ; CPU PWM pair: BAR0 + 48250h, two DWORDs.
        mov     esi, dword ptr cs:[MmioBase]
        add     esi, 048250h
        mov     edi, dword ptr cs:[ResultsLinear]
        mov     ecx, 2
        cld
        db      0F3h,067h,066h,0A5h     ; rep a32 movsd

        ; Legacy/native PWM pair: BAR0 + 61250h.
        mov     esi, dword ptr cs:[MmioBase]
        add     esi, 061250h
        mov     edi, dword ptr cs:[ResultsLinear]
        add     edi, 8
        mov     ecx, 2
        db      0F3h,067h,066h,0A5h

        ; PCH PWM pair: BAR0 + C8250h.
        mov     esi, dword ptr cs:[MmioBase]
        add     esi, 0C8250h
        mov     edi, dword ptr cs:[ResultsLinear]
        add     edi, 16
        mov     ecx, 2
        db      0F3h,067h,066h,0A5h

        mov     ax, SEL_DATA16
        mov     ds, ax
        mov     es, ax
        mov     ss, ax

        mov     eax, cr0
        and     al, 0FEh
        mov     cr0, eax

        db      0EAh
        dw      offset RealModeReturn
        dw      0000h
ReturnSegment equ ($-2)

RealModeReturn:
        mov     ax, cs
        mov     ds, ax
        mov     es, ax
        mov     ss, ax

        mov     al, byte ptr [SavedPort70]
        out     70h, al
        push    word ptr [SavedFlags]
        popf

        mov     dx, offset MsgValues
        call    PrintZ

        mov     dx, offset LCpu2
        call    PrintZ
        mov     eax, dword ptr [Results+0]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset LCpu
        call    PrintZ
        mov     eax, dword ptr [Results+4]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset LNative2
        call    PrintZ
        mov     eax, dword ptr [Results+8]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset LNative
        call    PrintZ
        mov     eax, dword ptr [Results+12]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset LPch1
        call    PrintZ
        mov     eax, dword ptr [Results+16]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset LPch2
        call    PrintZ
        mov     eax, dword ptr [Results+20]
        call    PrintHex32
        call    PrintCRLF

        ; Decode likely period/duty halves for the two CTL-style registers.
        mov     dx, offset MsgDecode
        call    PrintZ

        mov     dx, offset LNativePeriod
        call    PrintZ
        mov     ax, word ptr [Results+14]
        call    PrintHex16
        mov     dx, offset LDuty
        call    PrintZ
        mov     ax, word ptr [Results+12]
        call    PrintHex16
        call    PrintCRLF

        mov     dx, offset LPchPeriod
        call    PrintZ
        mov     ax, word ptr [Results+22]
        call    PrintHex16
        mov     dx, offset LDuty
        call    PrintZ
        mov     ax, word ptr [Results+20]
        call    PrintHex16
        call    PrintCRLF

        mov     dx, offset MsgDone
        call    PrintZ

        call    DisableA20IfNeeded
        mov     ax, 4C00h
        int     21h

PrepareProtectedMode proc near
        push    ax
        push    bx
        push    dx
        push    eax

        xor     eax, eax
        mov     ax, cs
        shl     eax, 4

        mov     bx, offset GdtCode16
        call    SetDescriptorBase
        mov     bx, offset GdtData16
        call    SetDescriptorBase

        mov     edx, eax
        xor     eax, eax
        mov     ax, offset GdtStart
        add     eax, edx
        mov     dword ptr [Gdtr+2], eax

        mov     eax, edx
        xor     edx, edx
        mov     dx, offset Results
        add     eax, edx
        mov     dword ptr [ResultsLinear], eax

        mov     ax, cs
        mov     word ptr cs:[ReturnSegment], ax

        pop     eax
        pop     dx
        pop     bx
        pop     ax
        ret
PrepareProtectedMode endp

SetDescriptorBase proc near
        mov     word ptr [bx+2], ax
        ror     eax, 16
        mov     byte ptr [bx+4], al
        mov     byte ptr [bx+7], ah
        ror     eax, 16
        ret
SetDescriptorBase endp

DisableA20IfNeeded proc near
        cmp     byte ptr [A20EnabledByUs], 0
        je      A20Done
        mov     ah, 06h
        call    dword ptr cs:[XmsEntry]
        mov     byte ptr [A20EnabledByUs], 0
A20Done:
        ret
DisableA20IfNeeded endp

PciReadFailed:
        mov     dx, offset MsgPciFail
        call    PrintZ
        jmp     ExitError

BarInvalid:
        mov     dx, offset MsgBarInvalid
        call    PrintZ
        jmp     ExitError

XmsNotPresent:
        mov     dx, offset MsgNoXms
        call    PrintZ
        jmp     ExitError

A20EnableFailed:
        mov     byte ptr [XmsError], bl
        mov     dx, offset MsgA20Fail
        call    PrintZ
        mov     al, byte ptr [XmsError]
        call    PrintHex8
        call    PrintCRLF
        jmp     ExitError

ExitError:
        call    DisableA20IfNeeded
        mov     ax, 4C01h
        int     21h

PciReadDword proc near
        mov     ax, 0B10Ah
        xor     bh, bh
        mov     bl, 10h
        int     1Ah
        ret
PciReadDword endp

PrintCRLF proc near
        mov     dx, offset MsgCRLF
        call    PrintZ
        ret
PrintCRLF endp

PrintZ proc near
        push    ax
        push    si
        mov     si, dx
PZLoop:
        lodsb
        or      al, al
        jz      PZDone
        mov     dl, al
        call    PutCh
        jmp     PZLoop
PZDone:
        pop     si
        pop     ax
        ret
PrintZ endp

PutCh proc near
        push    ax
        mov     ah, 02h
        int     21h
        pop     ax
        ret
PutCh endp

PrintHex32 proc near
        push    eax
        ror     eax, 16
        call    PrintHex16
        ror     eax, 16
        call    PrintHex16
        pop     eax
        ret
PrintHex32 endp

PrintHex16 proc near
        push    ax
        mov     al, ah
        call    PrintHex8
        pop     ax
        call    PrintHex8
        ret
PrintHex16 endp

PrintHex8 proc near
        push    ax
        push    bx
        mov     bl, al
        mov     al, bl
        shr     al, 4
        call    PrintNibble
        mov     al, bl
        and     al, 0Fh
        call    PrintNibble
        pop     bx
        pop     ax
        ret
PrintHex8 endp

PrintNibble proc near
        and     al, 0Fh
        cmp     al, 9
        jbe     NibbleDigit
        add     al, 'A'-10
        jmp     short NibbleOut
NibbleDigit:
        add     al, '0'
NibbleOut:
        mov     dl, al
        call    PutCh
        ret
PrintNibble endp

; GDT
GdtStart:
        dq 0

GdtCode16:
        dw 0FFFFh, 0000h
        db 00h, 09Ah, 00h, 00h

GdtData16:
        dw 0FFFFh, 0000h
        db 00h, 092h, 00h, 00h

GdtFlat:
        dw 0FFFFh, 0000h
        db 00h, 092h, 0CFh, 00h
GdtEnd:

Gdtr:
        dw GdtEnd-GdtStart-1
        dd 0

MsgTitle:
        db 13,10,'BLCPWM - T430 Ivy Bridge Backlight PWM Diagnostic',13,10
        db 'READ-ONLY: PCI configuration and graphics MMIO reads only.',13,10,0
MsgBar0:
        db 'Graphics MMIO BAR0: ',0
MsgPciF4:
        db 'PCI config F4h DWORD: ',0
MsgRead:
        db 'Entering protected mode to sample PWM registers...',13,10,0
MsgValues:
        db 13,10,'Raw register values:',13,10,0
MsgDecode:
        db 13,10,'CTL-style high/low 16-bit fields:',13,10,0
MsgDone:
        db 13,10,'Read-only PWM diagnostic complete.',13,10,0

MsgPciFail:
        db 'PCI BIOS configuration read failed.',13,10,0
MsgBarInvalid:
        db 'BAR0 is zero; refusing MMIO access.',13,10,0
MsgNoXms:
        db 'No XMS manager detected; A20 was not changed.',13,10,0
MsgA20Fail:
        db 'XMS could not enable A20; error BL=',0
MsgCRLF:
        db 13,10,0

LCpu2:
        db '  +48250 BLC_PWM_CPU_CTL2: ',0
LCpu:
        db '  +48254 BLC_PWM_CPU_CTL : ',0
LNative2:
        db '  +61250 BLC_PWM_CTL2    : ',0
LNative:
        db '  +61254 BLC_PWM_CTL     : ',0
LPch1:
        db '  +C8250 BLC_PWM_PCH_CTL1: ',0
LPch2:
        db '  +C8254 BLC_PWM_PCH_CTL2: ',0
LNativePeriod:
        db '  Native CTL: period/high=',0
LPchPeriod:
        db '  PCH CTL2  : period/high=',0
LDuty:
        db ' duty/low=',0

MmioBase       dd 0
PciF4          dd 0
ResultsLinear  dd 0
XmsEntry       dd 0
SavedFlags     dw 0
SavedPort70    db 0
A20EnabledByUs db 0
XmsError       db 0

Results        db 24 dup (0)

end start
