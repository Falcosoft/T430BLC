; BLCINIT.ASM
; ThinkPad T430 boot-time LCD brightness initializer
; Intel Ivy Bridge / HD Graphics 4000
;
; CONFIG.SYS:
;   DEVICE=C:\DOS\HIMEM.SYS
;   DEVICE=C:\DOS\BLCINIT.SYS 01E7
;   DEVICE=C:\DOS\EMM386.EXE RAM
;
; BLCINIT must load after HIMEM.SYS and before EMM386.EXE.
;
; BUILD WITH BORLAND TASM/TLINK/EXE2BIN:
;   TASM /m9 BLCINIT.ASM
;   TLINK /x BLCINIT.OBJ,BLCINIT.EXE
;   EXE2BIN BLCINIT.EXE BLCINIT.SYS
;
; Do NOT use TLINK /t. A COM image requires an entry point at offset 100h,
; while a DOS device driver must begin with its device header at offset 0.
;
; The initialization code:
;   - parses one 1..4 digit hexadecimal PWM duty from CONFIG.SYS
;   - reads graphics BAR0 from PCI 00:02.0
;   - enables A20 through HIMEM/XMS
;   - temporarily enters protected mode
;   - reads maximum PWM from BAR0+C8254h, upper 16 bits
;   - clamps the requested duty
;   - writes only BAR0+48254h, preserving its upper 16 bits
;   - verifies the write by readback
;   - returns to real mode and releases almost all driver memory
;
; The resident part is only the DOS device header, request pointer,
; strategy routine, and inert interrupt routine.
;
; VERIFIED:
;   Tested successfully on a Lenovo ThinkPad T430 running real MS-DOS.

.model tiny
.386p
.code
org 0

include T430LCD.INC

; ----------------------------------------------------------------------
; Resident DOS character-device portion
; ----------------------------------------------------------------------

DeviceHeader:
        dd      0FFFFFFFFh
        dw      8000h                   ; character device
        dw      Strategy
        dw      Interrupt
        db      'BLCINIT$'              ; exactly 8 characters

RequestOffset   dw 0
RequestSegment  dw 0
Initialized     db 0

Strategy proc far
        mov     cs:[RequestOffset], bx
        mov     cs:[RequestSegment], es
        retf
Strategy endp

Interrupt proc far
        pushf
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es

        push    cs
        pop     ds

        mov     bx, [RequestOffset]
        mov     es, [RequestSegment]
        mov     al, es:[bx+2]           ; request command

        cmp     al, 0
        jne     DriverUnknown
        cmp     byte ptr [Initialized], 0
        jne     DriverUnknown

        mov     byte ptr [Initialized], 1
        call    InitDriver
        jmp     short DriverExit

DriverUnknown:
        mov     word ptr es:[bx+3], 8103h ; error + done + unknown command

DriverExit:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        popf
        retf
Interrupt endp

ResidentEnd label byte

; Everything from here onward is discarded after initialization.
; ----------------------------------------------------------------------

InitDriver proc near
        ; ES:BX still addresses the initialization request packet.
        mov     word ptr es:[bx+0Eh], offset ResidentEnd
        mov     word ptr es:[bx+10h], cs
        ; Request +12h/+14h still contains the CONFIG.SYS line pointer.
        ; Do not overwrite it until after ParseConfigLine.

        mov     dx, offset MsgTitle
        call    PrintZ

        call    ParseConfigLine
        ; On return this field is the BPB-array pointer. Character drivers
        ; return 0000:0000, but only after consuming its input line pointer.
        mov     word ptr es:[bx+12h], 0
        mov     word ptr es:[bx+14h], 0
        jnc     InitParsed

        mov     dx, offset MsgUsage
        call    PrintZ
        mov     word ptr es:[bx+3], 810Ch ; error + done + general failure
        ret

InitParsed:
        mov     dx, offset MsgRequested
        call    PrintZ
        mov     ax, [RequestedDuty]
        call    PrintHex16
        call    PrintCRLF

        ; PCI BIOS read: bus 0, device 2, function 0, BAR0 offset 10h.
        mov     di, 10h
        call    PciReadDword
        jc      InitPciFail

        mov     eax, ecx
        and     eax, 0FFFFFFF0h
        mov     [MmioBase], eax
        test    eax, eax
        jz      InitBarFail

        mov     dx, offset MsgBar0
        call    PrintZ
        call    PrintHex32
        call    PrintCRLF

        ; HIMEM.SYS/XMS must already be loaded.
        mov     ax, 4300h
        int     2Fh
        cmp     al, 80h
        jne     InitNoXms

        mov     ax, 4310h
        int     2Fh
        mov     word ptr [XmsEntry], bx
        mov     word ptr [XmsEntry+2], es

        push    ds
        pop     es
        mov     ah, 05h                 ; local enable A20
        call    dword ptr cs:[XmsEntry]
        or      ax, ax
        jz      InitA20Fail
        mov     byte ptr [A20EnabledByUs], 1

        call    PrepareProtectedMode

        ; A SYS driver cannot assume DOS called it with SS=CS.
        ; Save DOS's stack and use a private stack whose base matches the
        ; protected-mode data descriptor.
        pushf
        pop     [SavedFlags]
        cli
        mov     [SavedSS], ss
        mov     [SavedSP], sp
        mov     ax, cs
        mov     ss, ax
        mov     sp, offset LocalStackTop

        in      al, 70h
        mov     [SavedPort70], al
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

        ; Read CPU PWM enable/control.
        mov     esi, dword ptr es:[MmioBase]
        add     esi, PWM_CPU_CTL2_OFFSET
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[CpuCtl2], eax
        mov     byte ptr es:[Checkpoint], 2

        ; Read original duty/control.
        mov     esi, dword ptr es:[MmioBase]
        add     esi, PWM_CPU_CTL_OFFSET
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[OriginalCpuCtl], eax
        mov     byte ptr es:[Checkpoint], 3

        ; Read maximum from PCH control upper word.
        mov     esi, dword ptr es:[MmioBase]
        add     esi, PWM_PCH_CTL2_OFFSET
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[PchCtl2], eax
        mov     edx, eax
        shr     edx, 16
        mov     word ptr es:[MaximumDuty], dx
        mov     byte ptr es:[Checkpoint], 4

        test    dx, dx
        jz      PmNoMaximum

        movzx   ecx, word ptr es:[RequestedDuty]
        movzx   edx, word ptr es:[MaximumDuty]
        cmp     ecx, edx
        jbe     PmDutyInRange
        mov     ecx, edx
PmDutyInRange:
        mov     word ptr es:[AppliedDuty], cx

        mov     eax, dword ptr es:[OriginalCpuCtl]
        and     eax, 0FFFF0000h
        or      eax, ecx
        mov     dword ptr es:[WrittenCpuCtl], eax
        mov     byte ptr es:[Checkpoint], 5

        ; Write only CPU PWM duty/control register.
        mov     esi, dword ptr es:[MmioBase]
        add     esi, PWM_CPU_CTL_OFFSET
        MMIO_WRITE_EAX_ESI
        mov     byte ptr es:[Checkpoint], 6

        ; Readback serializes and verifies the posted write.
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[ReadbackCpuCtl], eax
        mov     byte ptr es:[Checkpoint], 7

        mov     edx, eax
        and     edx, 0000FFFFh
        movzx   ecx, word ptr es:[AppliedDuty]
        cmp     edx, ecx
        jne     PmVerifyFailed

        mov     byte ptr es:[PmStatus], 0
        mov     byte ptr es:[Checkpoint], 8
        jmp     PmReturn

PmNoMaximum:
        mov     byte ptr es:[PmStatus], 1
        jmp     PmReturn

PmVerifyFailed:
        mov     byte ptr es:[PmStatus], 2

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

        mov     al, [SavedPort70]
        out     70h, al

        ; Restore DOS's original stack while interrupts remain disabled.
        mov     ax, [SavedSS]
        mov     dx, [SavedSP]
        mov     ss, ax
        mov     sp, dx
        push    word ptr cs:[SavedFlags]
        popf

        call    DisableA20IfNeeded

        ; Reload request packet pointer because BX/ES were used above.
        mov     bx, cs:[RequestOffset]
        mov     es, cs:[RequestSegment]

        mov     al, cs:[PmStatus]
        cmp     al, 0
        je      InitSuccess
        cmp     al, 1
        je      InitNoMaximum
        jmp     InitVerifyFail

InitSuccess:
        mov     dx, offset MsgSuccess1
        call    PrintZ
        mov     ax, cs:[AppliedDuty]
        call    PrintHex16
        mov     dx, offset MsgSuccess2
        call    PrintZ
        mov     ax, cs:[MaximumDuty]
        call    PrintHex16
        call    PrintCRLF

        ; Printing routines use BX, so reload the DOS request packet pointer.
        mov     bx, cs:[RequestOffset]
        mov     es, cs:[RequestSegment]
        mov     word ptr es:[bx+3], 0100h ; done, success
        ret

InitNoMaximum:
        mov     dx, offset MsgNoMaximum
        call    PrintZ
        jmp     InitFailure

InitVerifyFail:
        mov     dx, offset MsgVerifyFail
        call    PrintZ
        jmp     InitFailure

InitPciFail:
        mov     dx, offset MsgPciFail
        call    PrintZ
        jmp     InitFailure

InitBarFail:
        mov     dx, offset MsgBarFail
        call    PrintZ
        jmp     InitFailure

InitNoXms:
        mov     dx, offset MsgNoXms
        call    PrintZ
        jmp     InitFailure

InitA20Fail:
        mov     dx, offset MsgA20Fail
        call    PrintZ

InitFailure:
        call    DisableA20IfNeeded
        mov     bx, cs:[RequestOffset]
        mov     es, cs:[RequestSegment]
        mov     word ptr es:[bx+3], 810Ch ; error + done + general failure
        ret
InitDriver endp

; ----------------------------------------------------------------------
; Parse first argument after driver filename from CONFIG.SYS.
; Request packet +12h contains far pointer to text after '='.
; Accepts exactly one 1..4 digit hexadecimal token.
; ----------------------------------------------------------------------
ParseConfigLine proc near
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    es

        mov     bx, [RequestOffset]
        mov     es, [RequestSegment]
        mov     si, es:[bx+12h]
        mov     ax, es:[bx+14h]
        mov     es, ax

        ; Skip driver filename.
ParseFindSpace:
        mov     al, es:[si]
        cmp     al, 0
        je      ParseBad
        cmp     al, 0Dh
        je      ParseBad
        cmp     al, 0Ah
        je      ParseBad
        cmp     al, ' '
        je      ParseSkipSpace
        cmp     al, 9
        je      ParseSkipSpace
        inc     si
        jmp     ParseFindSpace

ParseSkipSpace:
        mov     al, es:[si]
        cmp     al, ' '
        je      ParseSkipOne
        cmp     al, 9
        jne     ParseStart
ParseSkipOne:
        inc     si
        jmp     ParseSkipSpace

ParseStart:
        xor     bx, bx
        xor     cx, cx

ParseDigit:
        mov     al, es:[si]
        cmp     al, ' '
        je      ParseEnd
        cmp     al, 9
        je      ParseEnd
        cmp     al, 0
        je      ParseEnd
        cmp     al, 0Dh
        je      ParseEnd
        cmp     al, 0Ah
        je      ParseEnd
        cmp     cx, 4
        jae     ParseBad

        call    HexToNibble
        jc      ParseBad
        shl     bx, 4
        xor     ah, ah
        or      bl, al
        inc     cx
        inc     si
        jmp     ParseDigit

ParseEnd:
        cmp     cx, 0
        je      ParseBad
        mov     [RequestedDuty], bx
        clc
        jmp     short ParseExit

ParseBad:
        stc

ParseExit:
        pop     es
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
ParseConfigLine endp

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
        cmp     byte ptr cs:[A20EnabledByUs], 0
        je      DisableA20Done
        mov     ah, 06h
        call    dword ptr cs:[XmsEntry]
        mov     byte ptr cs:[A20EnabledByUs], 0
DisableA20Done:
        ret
DisableA20IfNeeded endp

PciReadDword proc near
        mov     ax, 0B10Ah
        xor     bh, bh
        mov     bl, 10h
        int     1Ah
        ret
PciReadDword endp

; BIOS teletype output; avoids depending on DOS INT 21h during CONFIG.SYS.
PrintZ proc near
        push    ax
        push    bx
        push    si
        mov     si, dx
PrintZLoop:
        mov     al, cs:[si]
        inc     si
        or      al, al
        jz      PrintZDone
        mov     ah, 0Eh
        mov     bh, 0
        mov     bl, 7
        int     10h
        jmp     PrintZLoop
PrintZDone:
        pop     si
        pop     bx
        pop     ax
        ret
PrintZ endp

PrintCRLF proc near
        mov     dx, offset MsgCRLF
        call    PrintZ
        ret
PrintCRLF endp

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
        ; PrintHex8 keeps the original byte in BL. Preserve BX here because
        ; BIOS teletype output uses BH/BL and would otherwise replace BL
        ; with 07h, causing every second hex digit to be printed as '7'.
        push    bx
        and     al, 0Fh
        cmp     al, 9
        jbe     NibbleDigit
        add     al, 'A'-10
        jmp     short NibbleOutput
NibbleDigit:
        add     al, '0'
NibbleOutput:
        mov     ah, 0Eh
        mov     bh, 0
        mov     bl, 7
        int     10h
        pop     bx
        ret
PrintNibble endp

; ----------------------------------------------------------------------
; Protected-mode descriptors and initialization-only data
; ----------------------------------------------------------------------

GdtStart:
        dq      0
GdtCode16:
        dw      0FFFFh, 0000h
        db      00h, 09Ah, 00h, 00h
GdtData16:
        dw      0FFFFh, 0000h
        db      00h, 092h, 00h, 00h
GdtFlat:
        dw      0FFFFh, 0000h
        db      00h, 092h, 0CFh, 00h
GdtEnd:

Gdtr:
        dw      GdtEnd-GdtStart-1
        dd      0

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
SavedSS         dw 0
SavedSP         dw 0
SavedPort70     db 0
A20EnabledByUs  db 0
Checkpoint      db 0
PmStatus        db 0FFh

MsgTitle:
        db      13,10,'BLCINIT: ThinkPad T430 LCD brightness initializer',13,10,0
MsgUsage:
        db      'BLCINIT: missing/invalid PWM value.',13,10
        db      'Use: DEVICE=C:\DOS\BLCINIT.SYS 01E7',13,10,0
MsgRequested:
        db      'BLCINIT: requested PWM ',0
MsgBar0:
        db      ', graphics BAR0 ',0
MsgSuccess1:
        db      'BLCINIT: brightness set to ',0
MsgSuccess2:
        db      ' (maximum ',0
MsgNoMaximum:
        db      'BLCINIT: PWM maximum is zero; no write performed.',13,10,0
MsgVerifyFail:
        db      'BLCINIT: MMIO write verification failed.',13,10,0
MsgPciFail:
        db      'BLCINIT: PCI BIOS configuration read failed.',13,10,0
MsgBarFail:
        db      'BLCINIT: graphics BAR0 is zero.',13,10,0
MsgNoXms:
        db      'BLCINIT: HIMEM/XMS is unavailable.',13,10,0
MsgA20Fail:
        db      'BLCINIT: XMS could not enable A20.',13,10,0
MsgCRLF:
        db      13,10,0

LocalStack      db 256 dup (0)
LocalStackTop label byte

end DeviceHeader
