; ASPECT.ASM
; Lenovo ThinkPad T430 / Intel HD Graphics 4000
; Resident aspect-ratio corrector for the Lenovo ThinkPad T430.
;
; At installation it reads the active Fitter A destination size.
;
; If that destination is already 4:3, the BIOS output path is considered
; self-correcting and no TSR hook is installed.
;
; Otherwise ASPECT derives the largest centered 4:3 window dynamically and
; hooks INT 10h. After each mode set, it first checks whether the BIOS restored
; the same widescreen destination captured at installation. Only then does it
; reapply the 4:3 window.
;
; IMPORTANT:
; If the hook is invoked in virtual-8086 mode (for example through a DPMI
; host), it deliberately skips the privileged protected-mode transition.
; This prevents a fault, but means protected-mode games may remain stretched.
;
; Build:
;   TASM /m9 ASPECT.ASM
;   TLINK /t ASPECT.OBJ
;
; Install:
;   ASPECT
;
; Uninstall:
;   ASPECT /U
;
; Requirements:
;   - plain real-mode DOS for active correction
;   - HIMEM/XMS available during installation
;   - do not load twice
;
; The resident handler writes only dynamically calculated values to:
;   BAR0+68070h  Fitter A window position
;   BAR0+68074h  Fitter A window size
;
; It never modifies PF_A_CTL, PF_A_VSCALE, or PF_A_HSCALE.

.model tiny
.386p
.code
org 100h

include T430LCD.INC

PF_A_POS  equ PF_A_POS_OFFSET
PF_A_SIZE equ PF_A_SIZE_OFFSET

VBE_MODE_INFO_XRES equ 12h
VBE_MODE_INFO_YRES equ 14h

MUX_PRESENT       equ 0FEC0h
MUX_PRESENT_REPLY equ 0C0FEh
MUX_INFO          equ 0FEC1h
MUX_INFO_REPLY    equ 0C1FEh

RI_OLD10          equ 0
RI_OLD2F          equ 4
RI_XMS            equ 8
RI_ENV            equ 12

start:
        mov ax,cs
        mov ds,ax
        mov es,ax

        call IsUninstallCommand
        jc Uninstall

        mov dx,offset MsgTitle
        call PrintZ

        ; Refuse installation if already present.
        mov ax,MUX_PRESENT
        int 2Fh
        cmp ax,MUX_PRESENT_REPLY
        je AlreadyInstalled

        ; Read Intel graphics BAR0.
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

        ; Require XMS and globally enable A20. The resident interrupt handler
        ; must not call XMS from inside INT 10h.
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

        mov ah,03h                 ; XMS global enable A20
        call dword ptr cs:[XmsEntry]
        or ax,ax
        jz A20Fail

        call PrepareProtectedMode

        ; Save the environment block segment so /U can release it later.
        mov ax,word ptr cs:[2Ch]
        mov word ptr cs:[EnvironmentSegment],ax

        ; Read the current active output size and classify the output path.
        call DetectGeometryForeground
        jc GeometryFailed

        mov dx,offset MsgDetected
        call PrintZ
        mov ax,word ptr [NativeWidth]
        call PrintDec16
        mov dl,'x'
        call PutCh
        mov ax,word ptr [NativeHeight]
        call PrintDec16
        call PrintCRLF

        cmp byte ptr [CorrectionNeeded],0
        jne ShowAspectWindow

        mov dx,offset MsgAlready43
        call PrintZ
        mov ax,4C00h
        int 21h

ShowAspectWindow:
        mov dx,offset MsgAspectWindow
        call PrintZ
        mov ax,word ptr [AspectWidth]
        call PrintDec16
        mov dl,'x'
        call PutCh
        mov ax,word ptr [AspectHeight]
        call PrintDec16
        mov dx,offset MsgAt
        call PrintZ
        mov ax,word ptr [AspectX]
        call PrintDec16
        mov dl,','
        call PutCh
        mov ax,word ptr [AspectY]
        call PrintDec16
        call PrintCRLF

        ; Apply once to the current mode before installing the interrupt hooks.
        call ApplyAspectForeground
        jc GeometryFailed

        ; Save original INT 10h vector.
        mov ax,3510h
        int 21h
        mov word ptr [OldInt10],bx
        mov word ptr [OldInt10+2],es

        ; Save original INT 2Fh vector.
        mov ax,352Fh
        int 21h
        mov word ptr [OldInt2F],bx
        mov word ptr [OldInt2F+2],es

        ; Install INT 10h hook.
        push ds
        mov ax,cs
        mov ds,ax
        mov dx,offset NewInt10
        mov ax,2510h
        int 21h

        ; Install multiplex presence hook.
        mov dx,offset NewInt2F
        mov ax,252Fh
        int 21h
        pop ds

        mov dx,offset MsgInstalled
        call PrintZ

        ; INT 21h/AH=31h expects the number of paragraphs to keep,
        ; measured from the PSP segment. OFFSET ResidentEnd includes the
        ; COM image's 100h origin, so round it up at runtime.
        mov dx,offset ResidentEnd
        add dx,15
        mov cl,4
        shr dx,cl
        mov ax,3100h
        int 21h

GeometryFailed:
        mov dx,offset MsgGeometryFail
        call PrintZ
        mov ax,4C01h
        int 21h

AlreadyInstalled:
        mov dx,offset MsgAlready
        call PrintZ
        mov ax,4C01h
        int 21h
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
        mov ax,4C01h
        int 21h

; ----------------------------------------------------------------------
; Command-line check. CF set only for a standalone /U argument.
; ----------------------------------------------------------------------
IsUninstallCommand proc near
        xor bx,bx
        mov bl,byte ptr cs:[80h]
        mov si,81h

IucSkip:
        cmp bx,0
        je IucNo
        mov al,byte ptr cs:[si]
        cmp al,' '
        je IucNext
        cmp al,9
        jne IucHave
IucNext:
        inc si
        dec bx
        jmp IucSkip

IucHave:
        cmp al,'/'
        jne IucNo
        inc si
        mov al,byte ptr cs:[si]
        and al,0DFh
        cmp al,'U'
        jne IucNo
        inc si

IucTail:
        cmp bx,2
        jbe IucYes
        mov al,byte ptr cs:[si]
        cmp al,' '
        je IucTailNext
        cmp al,9
        jne IucNo
IucTailNext:
        inc si
        dec bx
        jmp IucTail

IucYes:
        stc
        ret
IucNo:
        clc
        ret
IsUninstallCommand endp

; ----------------------------------------------------------------------
; Safe TSR removal.
; ASPECT can be removed only while it remains the last handler on INT 10h
; and INT 2Fh. Otherwise restoring the saved vectors would break the chain.
; ----------------------------------------------------------------------
Uninstall:
        mov dx,offset MsgTitle
        call PrintZ

        mov ax,MUX_INFO
        int 2Fh
        cmp ax,MUX_INFO_REPLY
        jne UninstallNotInstalled

        ; Copy resident information before changing vectors or freeing memory.
        mov ax,es
        mov word ptr cs:[ResidentSegment],ax

        mov ax,word ptr es:[di+RI_OLD10]
        mov word ptr cs:[SavedOldInt10],ax
        mov ax,word ptr es:[di+RI_OLD10+2]
        mov word ptr cs:[SavedOldInt10+2],ax

        mov ax,word ptr es:[di+RI_OLD2F]
        mov word ptr cs:[SavedOldInt2F],ax
        mov ax,word ptr es:[di+RI_OLD2F+2]
        mov word ptr cs:[SavedOldInt2F+2],ax

        mov ax,word ptr es:[di+RI_XMS]
        mov word ptr cs:[SavedXmsEntry],ax
        mov ax,word ptr es:[di+RI_XMS+2]
        mov word ptr cs:[SavedXmsEntry+2],ax

        mov ax,word ptr es:[di+RI_ENV]
        mov word ptr cs:[SavedEnvironment],ax

        ; ASPECT must still own INT 10h.
        mov ax,3510h
        int 21h
        cmp bx,offset NewInt10
        jne UninstallUnsafe
        mov ax,es
        cmp ax,word ptr cs:[ResidentSegment]
        jne UninstallUnsafe

        ; ASPECT must still own INT 2Fh.
        mov ax,352Fh
        int 21h
        cmp bx,offset NewInt2F
        jne UninstallUnsafe
        mov ax,es
        cmp ax,word ptr cs:[ResidentSegment]
        jne UninstallUnsafe

        ; Restore INT 10h first.
        push ds
        mov ax,word ptr cs:[SavedOldInt10+2]
        mov ds,ax
        mov dx,word ptr cs:[SavedOldInt10]
        mov ax,2510h
        int 21h
        pop ds

        ; Restore INT 2Fh last, removing the multiplex API.
        push ds
        mov ax,word ptr cs:[SavedOldInt2F+2]
        mov ds,ax
        mov dx,word ptr cs:[SavedOldInt2F]
        mov ax,252Fh
        int 21h
        pop ds

        ; Balance the global A20 enable performed at installation.
        mov ah,04h
        call dword ptr cs:[SavedXmsEntry]

        ; Release the resident environment block first, if present.
        mov ax,word ptr cs:[SavedEnvironment]
        or ax,ax
        jz UninstallFreePsp
        mov es,ax
        mov ah,49h
        int 21h

UninstallFreePsp:
        mov ax,word ptr cs:[ResidentSegment]
        mov es,ax
        mov ah,49h
        int 21h
        jc UninstallFreeFailed

        mov dx,offset MsgUninstalled
        call PrintZ
        mov ax,4C00h
        int 21h

UninstallNotInstalled:
        mov dx,offset MsgNotInstalled
        call PrintZ
        mov ax,4C01h
        int 21h

UninstallUnsafe:
        mov dx,offset MsgUnsafeUnload
        call PrintZ
        mov ax,4C01h
        int 21h

UninstallFreeFailed:
        mov dx,offset MsgFreeFailed
        call PrintZ
        mov ax,4C01h
        int 21h

; ----------------------------------------------------------------------
; INT 2Fh multiplex presence check.
; Input AX=FEC0h -> output AX=C0FEh.
; ----------------------------------------------------------------------
NewInt2F proc far
        cmp ax,MUX_PRESENT
        je MuxPresent
        cmp ax,MUX_INFO
        je MuxInfo
        jmp dword ptr cs:[OldInt2F]

MuxPresent:
        mov ax,MUX_PRESENT_REPLY
        iret

MuxInfo:
        mov ax,MUX_INFO_REPLY
        push cs
        pop es
        mov di,offset ResidentInfo
        iret
NewInt2F endp

; ----------------------------------------------------------------------
; INT 10h hook.
; Calls the original BIOS first. Reapplies aspect only for mode-set calls.
; ----------------------------------------------------------------------
NewInt10 proc far
        cmp     ah,00h
        je      HookLegacyModeSet
        cmp     ax,4F02h
        je      HookVbeModeSet
        jmp     dword ptr cs:[OldInt10]

HookLegacyModeSet:
        mov     byte ptr cs:[ModeSetKind],1
        jmp     short HookCallOriginal

HookVbeModeSet:
        mov     byte ptr cs:[ModeSetKind],2
        mov     word ptr cs:[RequestedVbeMode],bx

HookCallOriginal:
        pushf
        call    dword ptr cs:[OldInt10]

        ; Preserve all caller-visible state returned by the BIOS.
        pushfd
        pushad
        push    ds
        push    es
        push    fs
        push    gs

        ; A failed VBE mode set must not trigger any fitting update.
        cmp     byte ptr cs:[ModeSetKind],2
        jne     HookCheckVm
        cmp     ax,004Fh
        jne     HookRestore

        ; Query the requested VBE mode through the original BIOS handler.
        ; VBE mode-info block offsets 12h/14h are XResolution/YResolution.
        mov     ax,cs
        mov     es,ax
        mov     di,offset VbeModeInfo
        mov     cx,word ptr cs:[RequestedVbeMode]
        and     cx,3FFFh             ; remove LFB and preserve-memory flags
        mov     ax,4F01h
        pushf
        call    dword ptr cs:[OldInt10]
        cmp     ax,004Fh
        jne     HookCheckVm

        mov     dx,word ptr cs:[NativeWidth]
        cmp     word ptr cs:[VbeModeInfo+VBE_MODE_INFO_XRES],dx
        jne     HookCheckVm
        mov     dx,word ptr cs:[NativeHeight]
        cmp     word ptr cs:[VbeModeInfo+VBE_MODE_INFO_YRES],dx
        je      HookRestore          ; native output mode: leave full-screen

HookCheckVm:
        ; If executing in virtual-8086 mode, privileged instructions would
        ; fault. Skip safely and leave the BIOS return state unchanged.
        pushfd
        pop     eax
        test    eax,00020000h
        jnz     HookRestore

        ; Avoid recursion/reentry.
        cmp     byte ptr cs:[Busy],0
        jne     HookRestore
        mov     byte ptr cs:[Busy],1

        ; Only correct when the BIOS restored the same widescreen
        ; destination captured during installation.
        call    CurrentSizeMatchesFromHook
        jc      HookClearBusy

        call    ApplyAspectFromHook

HookClearBusy:
        mov     byte ptr cs:[Busy],0

HookRestore:
        pop     gs
        pop     fs
        pop     es
        pop     ds
        popad
        popfd
        iret
NewInt10 endp

; ----------------------------------------------------------------------
; Foreground geometry detector used during installation.
; Reads PF_A_SIZE, classifies 4:3 vs widescreen, and computes the correction.
; ----------------------------------------------------------------------
DetectGeometryForeground proc near
        pushfd
        pushad
        push    ds
        push    es
        push    fs
        push    gs

        call    DetectGeometryCore
        mov     byte ptr cs:[ForegroundResult],0
        jnc     DetectForegroundRestore
        mov     byte ptr cs:[ForegroundResult],1
DetectForegroundRestore:
        pop     gs
        pop     fs
        pop     es
        pop     ds
        popad
        popfd
        cmp     byte ptr cs:[ForegroundResult],0
        jne     DetectForegroundFail
        clc
        ret
DetectForegroundFail:
        stc
        ret
DetectGeometryForeground endp

; ----------------------------------------------------------------------
; Hook wrapper: compare current PF_A_SIZE with the installation size.
; CF clear = equal, CF set = different or invalid.
; ----------------------------------------------------------------------
CurrentSizeMatchesFromHook proc near
        mov ax,ss
        mov word ptr cs:[CallerSS],ax
        mov word ptr cs:[CallerSP],sp

        cli
        mov ax,cs
        mov ss,ax
        mov sp,offset LocalStackTop

        call CurrentSizeMatchesCore

        cli
        mov ax,word ptr cs:[CallerSS]
        mov ss,ax
        mov sp,word ptr cs:[CallerSP]
        ret
CurrentSizeMatchesFromHook endp

; ----------------------------------------------------------------------
; Foreground wrapper used only during installation.
; ----------------------------------------------------------------------
ApplyAspectForeground proc near
        pushfd
        pushad
        push ds
        push es
        push fs
        push gs

        call ApplyAspectCore
        mov byte ptr cs:[ForegroundResult],0
        jnc ForegroundRestore
        mov byte ptr cs:[ForegroundResult],1
ForegroundRestore:
        pop gs
        pop fs
        pop es
        pop ds
        popad
        popfd
        cmp byte ptr cs:[ForegroundResult],0
        jne ForegroundFail
        clc
        ret
ForegroundFail:
        stc
        ret
ApplyAspectForeground endp

; ----------------------------------------------------------------------
; Hook wrapper. Switches away from the application's interrupt stack before
; entering protected mode.
; ----------------------------------------------------------------------
ApplyAspectFromHook proc near
        mov ax,ss
        mov word ptr cs:[CallerSS],ax
        mov word ptr cs:[CallerSP],sp

        cli
        mov ax,cs
        mov ss,ax
        mov sp,offset LocalStackTop

        call ApplyAspectCore

        cli
        mov ax,word ptr cs:[CallerSS]
        mov ss,ax
        mov sp,word ptr cs:[CallerSP]
        ret
ApplyAspectFromHook endp

; ----------------------------------------------------------------------
; Detect current fitter size and derive a centered 4:3 rectangle.
; CF clear on success.
; ----------------------------------------------------------------------
DetectGeometryCore proc near
        pushf
        pop word ptr cs:[SavedFlags]
        cli

        in al,70h
        mov byte ptr cs:[SavedPort70],al
        or al,80h
        out 70h,al

        lgdt fword ptr cs:[Gdtr]

        mov eax,cr0
        or al,1
        mov cr0,eax

        db 0EAh
        dw offset DetectPmEntry
        dw SEL_CODE16

DetectPmEntry:
        mov ax,SEL_DATA16
        mov ss,ax
        mov es,ax
        mov ax,SEL_FLAT
        mov ds,ax

        mov esi,dword ptr es:[MmioBase]
        add esi,PF_A_SIZE
        MMIO_READ_EAX_ESI
        mov dword ptr es:[NativeSize],eax

        mov edx,eax
        shr eax,16
        and edx,0FFFFh
        test ax,ax
        jz DetectPmFail
        test dx,dx
        jz DetectPmFail

        mov word ptr es:[NativeWidth],ax
        mov word ptr es:[NativeHeight],dx

        ; Exact 4:3 test: width*3 == height*4.
        movzx eax,word ptr es:[NativeWidth]
        imul eax,3
        movzx edx,word ptr es:[NativeHeight]
        shl edx,2
        cmp eax,edx
        jne DetectNeedsCorrection

        mov byte ptr es:[CorrectionNeeded],0
        mov byte ptr es:[DetectStatus],0
        jmp DetectPmLeave

DetectNeedsCorrection:
        mov byte ptr es:[CorrectionNeeded],1

        ; First try full output height: width = height*4/3.
        movzx eax,word ptr es:[NativeHeight]
        shl eax,2
        xor edx,edx
        mov ecx,3
        div ecx
        and ax,0FFFEh
        cmp ax,word ptr es:[NativeWidth]
        ja DetectFitByWidth

        mov word ptr es:[AspectWidth],ax
        mov ax,word ptr es:[NativeHeight]
        mov word ptr es:[AspectHeight],ax
        jmp short DetectCenter

DetectFitByWidth:
        mov ax,word ptr es:[NativeWidth]
        mov word ptr es:[AspectWidth],ax
        movzx eax,ax
        imul eax,3
        shr eax,2
        and ax,0FFFEh
        mov word ptr es:[AspectHeight],ax

DetectCenter:
        mov ax,word ptr es:[NativeWidth]
        sub ax,word ptr es:[AspectWidth]
        shr ax,1
        mov word ptr es:[AspectX],ax

        mov ax,word ptr es:[NativeHeight]
        sub ax,word ptr es:[AspectHeight]
        shr ax,1
        mov word ptr es:[AspectY],ax

        xor eax,eax
        mov ax,word ptr es:[AspectX]
        shl eax,16
        mov ax,word ptr es:[AspectY]
        mov dword ptr es:[AspectPos],eax

        xor eax,eax
        mov ax,word ptr es:[AspectWidth]
        shl eax,16
        mov ax,word ptr es:[AspectHeight]
        mov dword ptr es:[AspectSize],eax

        mov byte ptr es:[DetectStatus],0
        jmp short DetectPmLeave

DetectPmFail:
        mov byte ptr es:[DetectStatus],1

DetectPmLeave:
        mov ax,SEL_DATA16
        mov ds,ax
        mov es,ax
        mov ss,ax

        mov eax,cr0
        and al,0FEh
        mov cr0,eax

        db 0EAh
        dw offset DetectRmReturn
        dw 0000h
DetectReturnSegment equ ($-2)

DetectRmReturn:
        mov ax,cs
        mov ds,ax
        mov es,ax
        mov ss,ax

        mov al,byte ptr cs:[SavedPort70]
        out 70h,al
        push word ptr cs:[SavedFlags]
        popf

        cmp byte ptr cs:[DetectStatus],0
        jne DetectFailed
        clc
        ret
DetectFailed:
        stc
        ret
DetectGeometryCore endp

; ----------------------------------------------------------------------
; Read current PF_A_SIZE and compare with NativeSize captured at installation.
; CF clear = exact match; CF set = different.
; ----------------------------------------------------------------------
CurrentSizeMatchesCore proc near
        pushf
        pop word ptr cs:[SavedFlags]
        cli

        in al,70h
        mov byte ptr cs:[SavedPort70],al
        or al,80h
        out 70h,al

        lgdt fword ptr cs:[Gdtr]

        mov eax,cr0
        or al,1
        mov cr0,eax

        db 0EAh
        dw offset MatchPmEntry
        dw SEL_CODE16

MatchPmEntry:
        mov ax,SEL_DATA16
        mov ss,ax
        mov es,ax
        mov ax,SEL_FLAT
        mov ds,ax

        mov esi,dword ptr es:[MmioBase]
        add esi,PF_A_SIZE
        MMIO_READ_EAX_ESI
        mov dword ptr es:[CurrentSize],eax

        mov byte ptr es:[MatchStatus],1
        cmp eax,dword ptr es:[NativeSize]
        jne MatchPmLeave
        mov byte ptr es:[MatchStatus],0

MatchPmLeave:
        mov ax,SEL_DATA16
        mov ds,ax
        mov es,ax
        mov ss,ax

        mov eax,cr0
        and al,0FEh
        mov cr0,eax

        db 0EAh
        dw offset MatchRmReturn
        dw 0000h
MatchReturnSegment equ ($-2)

MatchRmReturn:
        mov ax,cs
        mov ds,ax
        mov es,ax
        mov ss,ax

        mov al,byte ptr cs:[SavedPort70]
        out 70h,al
        push word ptr cs:[SavedFlags]
        popf

        cmp byte ptr cs:[MatchStatus],0
        jne MatchDifferent
        clc
        ret
MatchDifferent:
        stc
        ret
CurrentSizeMatchesCore endp

; ----------------------------------------------------------------------
; Safe protected-mode write. Caller must not be in VM86 mode.
; Writes POS first and SIZE second, exactly like verified PFSET.
; ----------------------------------------------------------------------
ApplyAspectCore proc near
        pushf
        pop word ptr cs:[SavedFlags]
        cli

        in al,70h
        mov byte ptr cs:[SavedPort70],al
        or al,80h
        out 70h,al

        lgdt fword ptr cs:[Gdtr]

        mov eax,cr0
        or al,1
        mov cr0,eax

        db 0EAh
        dw offset PmEntry
        dw SEL_CODE16

PmEntry:
        mov ax,SEL_DATA16
        mov ss,ax
        mov es,ax

        mov ax,SEL_FLAT
        mov ds,ax

PmGeometryReady:
        mov esi,dword ptr es:[MmioBase]
        add esi,PF_A_POS
        mov eax,dword ptr es:[AspectPos]
        MMIO_WRITE_EAX_ESI

        mov esi,dword ptr es:[MmioBase]
        add esi,PF_A_SIZE
        mov eax,dword ptr es:[AspectSize]
        MMIO_WRITE_EAX_ESI

        ; Immediate readback verification.
        mov esi,dword ptr es:[MmioBase]
        add esi,PF_A_POS
        MMIO_READ_EAX_ESI
        mov dword ptr es:[ReadPos],eax

        mov esi,dword ptr es:[MmioBase]
        add esi,PF_A_SIZE
        MMIO_READ_EAX_ESI
        mov dword ptr es:[ReadSize],eax

        mov byte ptr es:[WriteStatus],0
        mov eax,dword ptr es:[ReadPos]
        cmp eax,dword ptr es:[AspectPos]
        jne PmVerifyFail
        mov eax,dword ptr es:[ReadSize]
        cmp eax,dword ptr es:[AspectSize]
        jne PmVerifyFail
        jmp short PmLeave

PmVerifyFail:
        mov byte ptr es:[WriteStatus],1

PmLeave:
        mov ax,SEL_DATA16
        mov ds,ax
        mov es,ax
        mov ss,ax

        mov eax,cr0
        and al,0FEh
        mov cr0,eax

        db 0EAh
        dw offset RmReturn
        dw 0000h
ReturnSegment equ ($-2)

RmReturn:
        mov ax,cs
        mov ds,ax
        mov es,ax
        mov ss,ax

        mov al,byte ptr cs:[SavedPort70]
        out 70h,al
        push word ptr cs:[SavedFlags]
        popf

        cmp byte ptr cs:[WriteStatus],0
        jne ApplyFailed
        clc
        ret
ApplyFailed:
        stc
        ret
ApplyAspectCore endp

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
        mov word ptr cs:[DetectReturnSegment],ax
        mov word ptr cs:[MatchReturnSegment],ax

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

PciReadDword proc near
        mov ax,0B10Ah
        xor bh,bh
        mov bl,10h
        int 1Ah
        ret
PciReadDword endp

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

PrintDec16 proc near
        push ax
        push bx
        push cx
        push dx

        xor cx,cx
        mov bx,10
        cmp ax,0
        jne PDConvert
        mov dl,'0'
        call PutCh
        jmp short PDDone

PDConvert:
        xor dx,dx
        div bx
        push dx
        inc cx
        test ax,ax
        jnz PDConvert

PDOutput:
        pop dx
        add dl,'0'
        call PutCh
        loop PDOutput

PDDone:
        pop dx
        pop cx
        pop bx
        pop ax
        ret
PrintDec16 endp

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

ResidentInfo label byte
OldInt10        dd 0
OldInt2F        dd 0
XmsEntry        dd 0
EnvironmentSegment dw 0

MmioBase        dd 0
ReadPos         dd 0
ReadSize        dd 0
NativeSize      dd 0
CurrentSize     dd 0
AspectPos       dd 0
AspectSize      dd 0
NativeWidth     dw 0
NativeHeight    dw 0
AspectWidth     dw 0
AspectHeight    dw 0
AspectX         dw 0
AspectY         dw 0
SavedFlags      dw 0
CallerSS        dw 0
CallerSP        dw 0
SavedPort70     db 0
WriteStatus     db 0
ForegroundResult db 0
Busy            db 0
ModeSetKind     db 0
RequestedVbeMode dw 0
CorrectionNeeded db 0
DetectStatus     db 0
MatchStatus      db 0

; VBE 2.0 ModeInfoBlock is 256 bytes.
VbeModeInfo     db 256 dup (0)

MsgTitle:
        db 13,10,'ASPECT - dynamic resident aspect-ratio corrector',13,10,0
MsgBar:
        db 'Graphics MMIO BAR0: ',0
MsgDetected:
        db 'Detected output resolution: ',0
MsgAspectWindow:
        db 'Calculated 4:3 window: ',0
MsgAt:
        db ' at ',0
MsgAlready43:
        db 'The current BIOS output path is already 4:3; no TSR hook was installed.',13,10,0
MsgInstalled:
        db 'Installed. Correction is applied only when the BIOS restores the',13,10
        db 'same widescreen fitter destination detected at installation.',13,10
        db 'Mode-dependent or already-correct external output paths are left untouched.',13,10,0
MsgGeometryFail:
        db 'Unable to detect or program a valid active fitter destination.',13,10,0
MsgAlready:
        db 'ASPECT is already installed.',13,10,0
MsgPciFail:
        db 'PCI BIOS BAR0 read failed.',13,10,0
MsgBarFail:
        db 'Graphics BAR0 is zero.',13,10,0
MsgNoXms:
        db 'HIMEM/XMS is unavailable.',13,10,0
MsgA20Fail:
        db 'XMS could not globally enable A20.',13,10,0
MsgUninstalled:
        db 'ASPECT was unloaded successfully.',13,10,0
MsgNotInstalled:
        db 'ASPECT is not installed.',13,10,0
MsgUnsafeUnload:
        db 'Cannot unload ASPECT: another TSR is installed after it.',13,10,0
MsgFreeFailed:
        db 'Interrupt vectors were restored, but DOS could not free the TSR block.',13,10,0
MsgCRLF:
        db 13,10,0

ResidentSegment  dw 0
SavedEnvironment dw 0
SavedOldInt10    dd 0
SavedOldInt2F    dd 0
SavedXmsEntry    dd 0

LocalStack db 512 dup (0)
LocalStackTop label byte

ResidentEnd label byte

end start
