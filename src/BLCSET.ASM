; BLCSET.ASM
; Lenovo ThinkPad T430 / Ivy Bridge Intel HD Graphics 4000
; LCD backlight PWM duty setter for real MS-DOS.
;
; BUILD:
;   TASM /m9 BLCSET.ASM
;   TLINK /t BLCSET.OBJ
;
; USAGE:
;   BLCSET <hex-duty>
;
; EXAMPLES:
;   BLCSET 0045
;   BLCSET 01E7
;   BLCSET 1155
;
; PROVEN REGISTER PATH:
;   BAR0 + 48250h  CPU PWM control/enable
;   BAR0 + 48254h  CPU PWM duty (low 16 bits)
;   BAR0 + C8254h  PCH PWM maximum (upper 16 bits)
;
; IMPORTANT IMPLEMENTATION DETAILS:
;   DS = flat 4 GB data segment for MMIO.
;   ES = writable program data segment for variables/checkpoints.
;   No protected-mode writes are made through CS.
;
; Explicit MMIO encodings in 16-bit protected-mode code:
;   67 66 8B 06       MOV EAX,[ESI]
;   67 66 89 06       MOV [ESI],EAX
;
; Only BAR0+48254h is written. Its upper 16 bits are preserved.
; The requested duty is clamped to the detected maximum.

.model tiny
.386p
.code
org 100h

include COMMON.INC

start:
        mov     ax, cs
        mov     ds, ax
        mov     es, ax

        mov     dx, offset MsgTitle
        call    PrintZ

        call    ParseCommandLine
        jc      BadSyntax

        mov     dx, offset MsgRequested
        call    PrintZ
        mov     ax, word ptr [RequestedDuty]
        call    PrintHex16
        call    PrintCRLF

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

        ; Use XMS only to enable A20.
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

        mov     dx, offset MsgEnter
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
        mov     es, ax

        mov     ax, SEL_FLAT
        mov     ds, ax

        mov     byte ptr es:[Checkpoint], 1

        ; Read CPU PWM control/enable at BAR0+48250h.
        mov     esi, dword ptr es:[MmioBase]
        add     esi, PWM_CPU_CTL2_OFFSET
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[CpuCtl2], eax
        mov     byte ptr es:[Checkpoint], 2

        ; Read current CPU PWM duty register at BAR0+48254h.
        mov     esi, dword ptr es:[MmioBase]
        add     esi, PWM_CPU_CTL_OFFSET
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[OriginalCpuCtl], eax
        mov     byte ptr es:[Checkpoint], 3

        ; Read PCH PWM maximum from upper 16 bits of BAR0+C8254h.
        mov     esi, dword ptr es:[MmioBase]
        add     esi, PWM_PCH_CTL2_OFFSET
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[PchCtl2], eax
        mov     edx, eax
        shr     edx, 16
        mov     word ptr es:[MaximumDuty], dx
        mov     byte ptr es:[Checkpoint], 4

        ; Reject a zero maximum rather than making an unsafe write.
        test    dx, dx
        jz      PmAbortNoMaximum

        ; Clamp requested duty to detected maximum.
        movzx   ecx, word ptr es:[RequestedDuty]
        movzx   edx, word ptr es:[MaximumDuty]
        cmp     ecx, edx
        jbe     DutyInRange
        mov     ecx, edx
DutyInRange:
        mov     word ptr es:[AppliedDuty], cx

        ; Preserve upper 16 bits of CPU_CTL and replace only low duty word.
        mov     eax, dword ptr es:[OriginalCpuCtl]
        and     eax, 0FFFF0000h
        or      eax, ecx
        mov     dword ptr es:[WrittenCpuCtl], eax
        mov     byte ptr es:[Checkpoint], 5

        ; Write BAR0+48254h only.
        mov     esi, dword ptr es:[MmioBase]
        add     esi, PWM_CPU_CTL_OFFSET
        MMIO_WRITE_EAX_ESI
        mov     byte ptr es:[Checkpoint], 6

        ; Serialize posted MMIO write by immediately reading same register.
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[ReadbackCpuCtl], eax
        mov     byte ptr es:[Checkpoint], 7

        ; Verify low 16 bits equal the applied duty.
        mov     edx, eax
        and     edx, 0000FFFFh
        movzx   ecx, word ptr es:[AppliedDuty]
        cmp     edx, ecx
        jne     PmVerifyFailed

        mov     byte ptr es:[PmStatus], 0
        mov     byte ptr es:[Checkpoint], 8
        jmp     PmReturn

PmAbortNoMaximum:
        mov     byte ptr es:[PmStatus], 1
        jmp     PmReturn

PmVerifyFailed:
        mov     byte ptr es:[PmStatus], 2
        jmp     PmReturn

PmReturn:
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

        mov     dx, offset MsgReturned
        call    PrintZ

        mov     dx, offset MsgCheckpoint
        call    PrintZ
        mov     al, byte ptr [Checkpoint]
        call    PrintHex8
        call    PrintCRLF

        mov     dx, offset MsgCpuCtl2
        call    PrintZ
        mov     eax, dword ptr [CpuCtl2]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgOriginal
        call    PrintZ
        mov     eax, dword ptr [OriginalCpuCtl]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgPchCtl2
        call    PrintZ
        mov     eax, dword ptr [PchCtl2]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgMaximum
        call    PrintZ
        mov     ax, word ptr [MaximumDuty]
        call    PrintHex16
        call    PrintCRLF

        mov     dx, offset MsgApplied
        call    PrintZ
        mov     ax, word ptr [AppliedDuty]
        call    PrintHex16
        call    PrintCRLF

        mov     dx, offset MsgWritten
        call    PrintZ
        mov     eax, dword ptr [WrittenCpuCtl]
        call    PrintHex32
        call    PrintCRLF

        mov     dx, offset MsgReadback
        call    PrintZ
        mov     eax, dword ptr [ReadbackCpuCtl]
        call    PrintHex32
        call    PrintCRLF

        mov     al, byte ptr [PmStatus]
        cmp     al, 0
        je      SetSucceeded
        cmp     al, 1
        je      NoMaximum
        cmp     al, 2
        je      VerifyFailed

        mov     dx, offset MsgUnknownStatus
        call    PrintZ
        jmp     ExitPmError

SetSucceeded:
        mov     dx, offset MsgSuccess
        call    PrintZ
        call    DisableA20IfNeeded
        mov     ax, 4C00h
        int     21h

NoMaximum:
        mov     dx, offset MsgNoMaximum
        call    PrintZ
        jmp     ExitPmError

VerifyFailed:
        mov     dx, offset MsgVerifyFailed
        call    PrintZ
        jmp     ExitPmError

ExitPmError:
        call    DisableA20IfNeeded
        mov     ax, 4C02h
        int     21h

; ----------------------------------------------------------------------
; Parse one hexadecimal command-line argument, 1..4 digits.
; Result: RequestedDuty
; CF=0 success, CF=1 error.
; ----------------------------------------------------------------------
ParseCommandLine proc near
        push    ax
        push    bx
        push    cx
        push    dx
        push    si

        xor     bx, bx
        xor     cx, cx
        mov     si, 81h
        xor     dx, dx
        mov     dl, byte ptr ds:[80h]

SkipLeading:
        cmp     dx, 0
        je      ParseFail
        mov     al, byte ptr [si]
        cmp     al, ' '
        jne     ParseDigits
        inc     si
        dec     dx
        jmp     SkipLeading

ParseDigits:
        cmp     dx, 0
        je      ParseDone
        mov     al, byte ptr [si]
        cmp     al, ' '
        je      ParseTrailing
        cmp     cx, 4
        jae     ParseFail

        call    HexToNibble
        jc      ParseFail

        shl     bx, 4
        xor     ah, ah
        or      bl, al
        inc     cx
        inc     si
        dec     dx
        jmp     ParseDigits

ParseTrailing:
        inc     si
        dec     dx
TrailingLoop:
        cmp     dx, 0
        je      ParseDone
        mov     al, byte ptr [si]
        cmp     al, ' '
        jne     ParseFail
        inc     si
        dec     dx
        jmp     TrailingLoop

ParseDone:
        cmp     cx, 0
        je      ParseFail
        mov     word ptr [RequestedDuty], bx
        clc
        jmp     ParseExit

ParseFail:
        stc

ParseExit:
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
ParseCommandLine endp

HexToNibble proc near
        cmp     al, '0'
        jb      HexBad
        cmp     al, '9'
        jbe     HexDigit
        and     al, 0DFh
        cmp     al, 'A'
        jb      HexBad
        cmp     al, 'F'
        ja      HexBad
        sub     al, 'A'-10
        clc
        ret
HexDigit:
        sub     al, '0'
        clc
        ret
HexBad:
        stc
        ret
HexToNibble endp

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

BadSyntax:
        mov     dx, offset MsgUsage
        call    PrintZ
        mov     ax, 4C01h
        int     21h

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
        db 13,10,'BLCSET - ThinkPad T430 LCD PWM duty setter',13,10,0
MsgUsage:
        db 'Usage: BLCSET <hex-duty>',13,10
        db 'Examples: BLCSET 0045   BLCSET 01E7   BLCSET 1155',13,10,0
MsgRequested:
        db 'Requested duty: ',0
MsgBar0:
        db 'Graphics MMIO BAR0: ',0
MsgEnter:
        db 'Entering protected mode...',13,10,0
MsgReturned:
        db 'Returned from protected mode.',13,10,0
MsgCheckpoint:
        db 'Final checkpoint: ',0
MsgCpuCtl2:
        db '  +48250 CPU_CTL2 : ',0
MsgOriginal:
        db '  +48254 original : ',0
MsgPchCtl2:
        db '  +C8254 PCH_CTL2 : ',0
MsgMaximum:
        db '  detected maximum: ',0
MsgApplied:
        db '  applied duty    : ',0
MsgWritten:
        db '  value written   : ',0
MsgReadback:
        db '  readback        : ',0
MsgSuccess:
        db 'Brightness duty changed and verified.',13,10,0
MsgNoMaximum:
        db 'Aborted: detected PWM maximum is zero; no MMIO write performed.',13,10,0
MsgVerifyFailed:
        db 'ERROR: MMIO write readback did not match requested duty.',13,10,0
MsgUnknownStatus:
        db 'ERROR: unknown protected-mode status.',13,10,0
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

MmioBase        dd 0
CpuCtl2         dd 0
OriginalCpuCtl  dd 0
PchCtl2         dd 0
WrittenCpuCtl   dd 0
ReadbackCpuCtl  dd 0
RequestedDuty   dw 0
MaximumDuty     dw 0
AppliedDuty     dw 0
XmsEntry        dd 0
SavedFlags      dw 0
SavedPort70     db 0
A20EnabledByUs  db 0
XmsError        db 0
Checkpoint      db 0
PmStatus        db 0FFh

end start
