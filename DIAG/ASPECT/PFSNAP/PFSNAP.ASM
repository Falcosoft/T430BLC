; PFSNAP.ASM
; Lenovo ThinkPad T430 / Intel HD Graphics 4000
; Read-only INT 10h panel-fitter and display-pipe snapshot TSR.
;
; Commands:
;   PFSNAP       install TSR
;   PFSNAP /I    install TSR
;   PFSNAP /D    dump captured snapshots
;
; The resident hook watches:
;   INT 10h AH=00h
;   INT 10h AX=4F02h
;
; It captures one snapshot before and one snapshot after the original BIOS
; mode-set handler. No graphics, PCI, OpRegion, or MMIO registers are written.
;
; Build:
;   TASM /m9 PFSNAP.ASM
;   TLINK /t PFSNAP.OBJ
;
; Run without EMM386 for the first tests.

.model tiny
.386p
.code
org 100h

include T430LCD.INC

SNAP_COUNT       equ 8
SNAP_DWORDS      equ 39
SNAP_HEADER_SIZE equ 12
SNAP_SIZE        equ SNAP_HEADER_SIZE + SNAP_DWORDS*4

; Snapshot header offsets.
S_PHASE          equ 0
S_KIND           equ 1
S_REQ_AX         equ 2
S_REQ_BX         equ 4
S_BIOS_AX        equ 6
S_SEQUENCE       equ 8
S_RESERVED       equ 10
S_DATA           equ 12

; Fitter register bases.
PF_A_POS         equ PF_A_POS_OFFSET
PF_B_POS         equ PF_B_POS_OFFSET
PF_C_POS         equ PF_C_POS_OFFSET

; Pipe timing/control registers.
PIPE_A_TIMING    equ PIPE_A_TIMING_OFFSET
PIPE_B_TIMING    equ PIPE_B_TIMING_OFFSET
PIPE_C_TIMING    equ PIPE_C_TIMING_OFFSET
PIPE_A_CONF      equ PIPE_A_CONF_OFFSET
PIPE_B_CONF      equ PIPE_B_CONF_OFFSET
PIPE_C_CONF      equ PIPE_C_CONF_OFFSET

; Multiplex functions.
MUX_QUERY        equ 0FEC2h
MUX_REPLY        equ 0C2FEh
MUX_CLEAR        equ 0FEC3h

start:
        mov     ax,cs
        mov     ds,ax
        mov     es,ax

        call    ParseCommand
        cmp     byte ptr cs:[Command],2
        je      DumpSnapshots
        cmp     byte ptr cs:[Command],3
        je      ClearSnapshots
        cmp     byte ptr cs:[Command],1
        je      Install
        jmp     Usage

; ----------------------------------------------------------------------
; Install resident hook.
; ----------------------------------------------------------------------
Install:
        mov     dx,offset MsgTitle
        call    PrintZ

        mov     ax,MUX_QUERY
        int     2Fh
        cmp     ax,MUX_REPLY
        je      AlreadyInstalled

        ; Read Intel graphics BAR0.
        mov     di,10h
        call    PciReadDword
        jc      PciFail
        mov     eax,ecx
        and     eax,0FFFFFFF0h
        mov     dword ptr cs:[MmioBase],eax
        test    eax,eax
        jz      BarFail

        mov     dx,offset MsgBar
        call    PrintZ
        call    PrintHex32
        call    PrintCRLF

        ; XMS is used only to globally enable A20 during installation.
        mov     ax,4300h
        int     2Fh
        cmp     al,80h
        jne     NoXms
        mov     ax,4310h
        int     2Fh
        mov     word ptr cs:[XmsEntry],bx
        mov     word ptr cs:[XmsEntry+2],es

        push    ds
        pop     es
        mov     ah,03h
        call    dword ptr cs:[XmsEntry]
        or      ax,ax
        jz      A20Fail

        call    PrepareProtectedMode

        ; Save vectors.
        mov     ax,3510h
        int     21h
        mov     word ptr cs:[OldInt10],bx
        mov     word ptr cs:[OldInt10+2],es

        mov     ax,352Fh
        int     21h
        mov     word ptr cs:[OldInt2F],bx
        mov     word ptr cs:[OldInt2F+2],es

        ; Install hooks.
        push    ds
        mov     ax,cs
        mov     ds,ax

        mov     dx,offset NewInt10
        mov     ax,2510h
        int     21h

        mov     dx,offset NewInt2F
        mov     ax,252Fh
        int     21h
        pop     ds

        mov     dx,offset MsgInstalled
        call    PrintZ

        ; Keep PSP + resident image, rounded up to paragraphs.
        mov     dx,offset ResidentEnd
        add     dx,15
        mov     cl,4
        shr     dx,cl
        mov     ax,3100h
        int     21h

AlreadyInstalled:
        mov     dx,offset MsgAlready
        call    PrintZ
        mov     ax,4C01h
        int     21h

PciFail:
        mov     dx,offset MsgPciFail
        call    PrintZ
        jmp     FatalExit
BarFail:
        mov     dx,offset MsgBarFail
        call    PrintZ
        jmp     FatalExit
NoXms:
        mov     dx,offset MsgNoXms
        call    PrintZ
        jmp     FatalExit
A20Fail:
        mov     dx,offset MsgA20Fail
        call    PrintZ
FatalExit:
        mov     ax,4C01h
        int     21h

; ----------------------------------------------------------------------
; INT 2Fh multiplex API.
; MUX_QUERY:
;   AX=MUX_REPLY
;   ES:DI -> SnapshotBuffer
;   BX = valid record count
;   CX = record size
;   DX = next write index
;   SI = skipped VM86 capture count
;
; MUX_CLEAR clears the ring buffer and counters.
; ----------------------------------------------------------------------
NewInt2F proc far
        cmp     ax,MUX_QUERY
        je      MuxQuery
        cmp     ax,MUX_CLEAR
        je      MuxClear
        jmp     dword ptr cs:[OldInt2F]

MuxQuery:
        mov     ax,MUX_REPLY
        push    cs
        pop     es
        mov     di,offset SnapshotBuffer
        xor     bx,bx
        mov     bl,byte ptr cs:[SnapshotCount]
        mov     cx,SNAP_SIZE
        xor     dx,dx
        mov     dl,byte ptr cs:[SnapshotNext]
        mov     si,word ptr cs:[VmSkipped]
        iret

MuxClear:
        mov     byte ptr cs:[SnapshotCount],0
        mov     byte ptr cs:[SnapshotNext],0
        mov     word ptr cs:[SequenceCounter],0
        mov     word ptr cs:[VmSkipped],0
        mov     ax,MUX_REPLY
        iret
NewInt2F endp

; ----------------------------------------------------------------------
; INT 10h hook.
; ----------------------------------------------------------------------
NewInt10 proc far
        cmp     ah,00h
        je      SnapLegacy
        cmp     ax,4F02h
        je      SnapVbe
        jmp     dword ptr cs:[OldInt10]

SnapLegacy:
        cmp     byte ptr cs:[Busy],0
        jne     ChainInt10
        mov     byte ptr cs:[Busy],1
        mov     byte ptr cs:[CurrentKind],1
        mov     word ptr cs:[CurrentReqAx],ax
        mov     word ptr cs:[CurrentReqBx],bx
        jmp     short SnapBefore

SnapVbe:
        cmp     byte ptr cs:[Busy],0
        jne     ChainInt10
        mov     byte ptr cs:[Busy],1
        mov     byte ptr cs:[CurrentKind],2
        mov     word ptr cs:[CurrentReqAx],ax
        mov     word ptr cs:[CurrentReqBx],bx

SnapBefore:
        ; Preserve original request state around the before snapshot.
        pushfd
        pushad
        push    ds
        push    es
        push    fs
        push    gs

        mov     byte ptr cs:[CurrentPhase],0
        mov     word ptr cs:[CurrentBiosAx],0FFFFh
        call    CaptureIfSafe

        pop     gs
        pop     fs
        pop     es
        pop     ds
        popad
        popfd

        ; Execute the original BIOS mode-set handler.
        pushf
        call    dword ptr cs:[OldInt10]

        ; Preserve BIOS return state around the after snapshot.
        pushfd
        pushad
        push    ds
        push    es
        push    fs
        push    gs

        mov     byte ptr cs:[CurrentPhase],1
        mov     word ptr cs:[CurrentBiosAx],ax
        call    CaptureIfSafe

        mov     byte ptr cs:[Busy],0

        pop     gs
        pop     fs
        pop     es
        pop     ds
        popad
        popfd
        iret

ChainInt10:
        jmp     dword ptr cs:[OldInt10]
NewInt10 endp

; ----------------------------------------------------------------------
; Capture wrapper. VM86 calls are skipped safely.
; ----------------------------------------------------------------------
CaptureIfSafe proc near
        pushfd
        pop     eax
        test    eax,00020000h
        jz      CaptureRealMode
        inc     word ptr cs:[VmSkipped]
        ret

CaptureRealMode:
        mov     ax,ss
        mov     word ptr cs:[CallerSS],ax
        mov     word ptr cs:[CallerSP],sp

        cli
        mov     ax,cs
        mov     ss,ax
        mov     sp,offset LocalStackTop

        call    CaptureCore

        cli
        mov     ax,word ptr cs:[CallerSS]
        mov     ss,ax
        mov     sp,word ptr cs:[CallerSP]
        ret
CaptureIfSafe endp

; ----------------------------------------------------------------------
; Safe protected-mode snapshot reader.
; ----------------------------------------------------------------------
CaptureCore proc near
        pushf
        pop     word ptr cs:[SavedFlags]
        cli

        in      al,70h
        mov     byte ptr cs:[SavedPort70],al
        or      al,80h
        out     70h,al

        lgdt    fword ptr cs:[Gdtr]

        mov     eax,cr0
        or      al,1
        mov     cr0,eax

        db      0EAh
        dw      offset PmEntry
        dw      SEL_CODE16

PmEntry:
        mov     ax,SEL_DATA16
        mov     ss,ax
        mov     es,ax
        mov     ax,SEL_FLAT
        mov     ds,ax

        ; DI = SnapshotBuffer + SnapshotNext * SNAP_SIZE.
        xor     ax,ax
        mov     al,byte ptr es:[SnapshotNext]
        mov     bx,SNAP_SIZE
        mul     bx
        add     ax,offset SnapshotBuffer
        mov     di,ax

        ; Header.
        mov     al,byte ptr es:[CurrentPhase]
        mov     byte ptr es:[di+S_PHASE],al
        mov     al,byte ptr es:[CurrentKind]
        mov     byte ptr es:[di+S_KIND],al
        mov     ax,word ptr es:[CurrentReqAx]
        mov     word ptr es:[di+S_REQ_AX],ax
        mov     ax,word ptr es:[CurrentReqBx]
        mov     word ptr es:[di+S_REQ_BX],ax
        mov     ax,word ptr es:[CurrentBiosAx]
        mov     word ptr es:[di+S_BIOS_AX],ax
        mov     ax,word ptr es:[SequenceCounter]
        mov     word ptr es:[di+S_SEQUENCE],ax
        inc     word ptr es:[SequenceCounter]
        mov     word ptr es:[di+S_RESERVED],0

        add     di,S_DATA

        ; Fitter A, B and C: CTL, POS, SIZE, VSCALE, HSCALE.
        mov     ebx,PF_A_POS
        call    ReadFitter
        mov     ebx,PF_B_POS
        call    ReadFitter
        mov     ebx,PF_C_POS
        call    ReadFitter

        ; Pipe A, B and C: PIPECONF, HTOTAL, HBLANK, HSYNC,
        ; VTOTAL, VBLANK, VSYNC, PIPESRC.
        mov     ebx,PIPE_A_TIMING
        mov     ecx,PIPE_A_CONF
        call    ReadPipe
        mov     ebx,PIPE_B_TIMING
        mov     ecx,PIPE_B_CONF
        call    ReadPipe
        mov     ebx,PIPE_C_TIMING
        mov     ecx,PIPE_C_CONF
        call    ReadPipe

        ; Advance circular buffer.
        mov     al,byte ptr es:[SnapshotNext]
        inc     al
        cmp     al,SNAP_COUNT
        jb      StoreNext
        xor     al,al
StoreNext:
        mov     byte ptr es:[SnapshotNext],al

        cmp     byte ptr es:[SnapshotCount],SNAP_COUNT
        jae     PmLeave
        inc     byte ptr es:[SnapshotCount]

PmLeave:
        mov     ax,SEL_DATA16
        mov     ds,ax
        mov     es,ax
        mov     ss,ax

        mov     eax,cr0
        and     al,0FEh
        mov     cr0,eax

        db      0EAh
        dw      offset RmReturn
        dw      0000h
ReturnSegment equ ($-2)

RmReturn:
        mov     ax,cs
        mov     ds,ax
        mov     es,ax
        mov     ss,ax

        mov     al,byte ptr cs:[SavedPort70]
        out     70h,al
        push    word ptr cs:[SavedFlags]
        popf
        ret
CaptureCore endp

; EBX = fitter POS register offset. DI = output pointer.
ReadFitter proc near
        push    eax
        push    esi

        mov     esi,dword ptr es:[MmioBase]
        add     esi,ebx
        add     esi,10h             ; CTL
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[di],eax
        add     di,4

        mov     esi,dword ptr es:[MmioBase]
        add     esi,ebx             ; POS
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[di],eax
        add     di,4

        add     esi,4               ; SIZE
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[di],eax
        add     di,4

        add     esi,0Ch             ; VSCALE
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[di],eax
        add     di,4

        add     esi,0Ch             ; HSCALE
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[di],eax
        add     di,4

        pop     esi
        pop     eax
        ret
ReadFitter endp

; EBX = timing base, ECX = PIPECONF offset. DI = output pointer.
ReadPipe proc near
        push    eax
        push    esi

        mov     esi,dword ptr es:[MmioBase]
        add     esi,ecx
        MMIO_READ_EAX_ESI
        mov     dword ptr es:[di],eax
        add     di,4

        mov     esi,dword ptr es:[MmioBase]
        add     esi,ebx

        MMIO_READ_EAX_ESI           ; HTOTAL
        mov     dword ptr es:[di],eax
        add     di,4
        add     esi,4

        MMIO_READ_EAX_ESI           ; HBLANK
        mov     dword ptr es:[di],eax
        add     di,4
        add     esi,4

        MMIO_READ_EAX_ESI           ; HSYNC
        mov     dword ptr es:[di],eax
        add     di,4
        add     esi,4

        MMIO_READ_EAX_ESI           ; VTOTAL
        mov     dword ptr es:[di],eax
        add     di,4
        add     esi,4

        MMIO_READ_EAX_ESI           ; VBLANK
        mov     dword ptr es:[di],eax
        add     di,4
        add     esi,4

        MMIO_READ_EAX_ESI           ; VSYNC
        mov     dword ptr es:[di],eax
        add     di,4
        add     esi,8               ; skip VSYNCSHIFT at +18h, PIPESRC +1Ch

        MMIO_READ_EAX_ESI           ; PIPESRC
        mov     dword ptr es:[di],eax
        add     di,4

        pop     esi
        pop     eax
        ret
ReadPipe endp

; ----------------------------------------------------------------------
; Transient dump command.
; ----------------------------------------------------------------------
DumpSnapshots:
        mov     dx,offset MsgDumpTitle
        call    PrintZ

        mov     ax,MUX_QUERY
        int     2Fh
        cmp     ax,MUX_REPLY
        jne     NotInstalled

        mov     word ptr cs:[DumpBase],di
        mov     word ptr cs:[DumpSegment],es
        mov     word ptr cs:[DumpCount],bx
        mov     word ptr cs:[DumpRecordSize],cx
        mov     word ptr cs:[DumpNext],dx
        mov     word ptr cs:[DumpSkipped],si

        mov     dx,offset MsgCount
        call    PrintZ
        mov     ax,word ptr cs:[DumpCount]
        call    PrintDec16
        mov     dx,offset MsgSkipped
        call    PrintZ
        mov     ax,word ptr cs:[DumpSkipped]
        call    PrintDec16
        call    PrintCRLF

        cmp     word ptr cs:[DumpCount],0
        je      DumpDone

        ; Oldest record is index 0 until full; when full it is SnapshotNext.
        mov     ax,word ptr cs:[DumpCount]
        cmp     ax,SNAP_COUNT
        jb      DumpStartZero
        mov     ax,word ptr cs:[DumpNext]
        jmp     short DumpHaveStart
DumpStartZero:
        xor     ax,ax
DumpHaveStart:
        mov     word ptr cs:[DumpIndex],ax
        mov     cx,word ptr cs:[DumpCount]

DumpLoop:
        push    cx

        mov     ax,word ptr cs:[DumpIndex]
        mov     bx,SNAP_SIZE
        mul     bx
        add     ax,word ptr cs:[DumpBase]
        mov     si,ax
        mov     ax,word ptr cs:[DumpSegment]
        mov     es,ax

        call    PrintOneSnapshot

        mov     ax,word ptr cs:[DumpIndex]
        inc     ax
        cmp     ax,SNAP_COUNT
        jb      DumpStoreIndex
        xor     ax,ax
DumpStoreIndex:
        mov     word ptr cs:[DumpIndex],ax

        pop     cx
        loop    DumpLoop

DumpDone:
        mov     ax,4C00h
        int     21h

ClearSnapshots:
        mov     ax,MUX_CLEAR
        int     2Fh
        cmp     ax,MUX_REPLY
        jne     NotInstalled
        mov     dx,offset MsgCleared
        call    PrintZ
        mov     ax,4C00h
        int     21h

NotInstalled:
        mov     dx,offset MsgNotInstalled
        call    PrintZ
        mov     ax,4C01h
        int     21h

; ES:SI points to one snapshot.
PrintOneSnapshot proc near
        mov     dx,offset MsgSeparator
        call    PrintZ

        mov     dx,offset MsgSequence
        call    PrintZ
        mov     ax,word ptr es:[si+S_SEQUENCE]
        call    PrintDec16

        mov     dx,offset MsgPhase
        call    PrintZ
        mov     al,byte ptr es:[si+S_PHASE]
        or      al,al
        jz      PrintBefore
        mov     dx,offset MsgAfter
        call    PrintZ
        jmp     short PrintKind
PrintBefore:
        mov     dx,offset MsgBefore
        call    PrintZ

PrintKind:
        mov     dx,offset MsgKind
        call    PrintZ
        mov     al,byte ptr es:[si+S_KIND]
        cmp     al,2
        je      PrintVbeKind
        mov     dx,offset MsgLegacy
        call    PrintZ
        jmp     short PrintRequest
PrintVbeKind:
        mov     dx,offset MsgVbe
        call    PrintZ

PrintRequest:
        mov     dx,offset MsgReqAx
        call    PrintZ
        mov     ax,word ptr es:[si+S_REQ_AX]
        call    PrintHex16
        mov     dx,offset MsgReqBx
        call    PrintZ
        mov     ax,word ptr es:[si+S_REQ_BX]
        call    PrintHex16
        mov     dx,offset MsgBiosAx
        call    PrintZ
        mov     ax,word ptr es:[si+S_BIOS_AX]
        call    PrintHex16
        call    PrintCRLF

        mov     di,si
        add     di,S_DATA

        mov     dx,offset MsgFitterA
        call    PrintFitterDump
        mov     dx,offset MsgFitterB
        call    PrintFitterDump
        mov     dx,offset MsgFitterC
        call    PrintFitterDump

        mov     dx,offset MsgPipeA
        call    PrintPipeDump
        mov     dx,offset MsgPipeB
        call    PrintPipeDump
        mov     dx,offset MsgPipeC
        call    PrintPipeDump
        ret
PrintOneSnapshot endp

; ES:DI points to 5 fitter DWORDs; advances DI.
PrintFitterDump proc near
        call    PrintZ
        mov     eax,dword ptr es:[di]
        call    PrintHex32
        mov     dx,offset MsgPos
        call    PrintZ
        mov     eax,dword ptr es:[di+4]
        call    PrintHex32
        mov     dx,offset MsgSize
        call    PrintZ
        mov     eax,dword ptr es:[di+8]
        call    PrintHex32
        mov     dx,offset MsgVScale
        call    PrintZ
        mov     eax,dword ptr es:[di+12]
        call    PrintHex32
        mov     dx,offset MsgHScale
        call    PrintZ
        mov     eax,dword ptr es:[di+16]
        call    PrintHex32
        call    PrintCRLF
        add     di,20
        ret
PrintFitterDump endp

; ES:DI points to 8 pipe DWORDs; advances DI.
PrintPipeDump proc near
        call    PrintZ
        mov     eax,dword ptr es:[di]
        call    PrintHex32
        mov     dx,offset MsgHTotal
        call    PrintZ
        mov     eax,dword ptr es:[di+4]
        call    PrintHex32
        mov     dx,offset MsgHBlank
        call    PrintZ
        mov     eax,dword ptr es:[di+8]
        call    PrintHex32
        mov     dx,offset MsgHSync
        call    PrintZ
        mov     eax,dword ptr es:[di+12]
        call    PrintHex32
        mov     dx,offset MsgVTotal
        call    PrintZ
        mov     eax,dword ptr es:[di+16]
        call    PrintHex32
        mov     dx,offset MsgVBlank
        call    PrintZ
        mov     eax,dword ptr es:[di+20]
        call    PrintHex32
        mov     dx,offset MsgVSync
        call    PrintZ
        mov     eax,dword ptr es:[di+24]
        call    PrintHex32
        mov     dx,offset MsgPipeSrc
        call    PrintZ
        mov     eax,dword ptr es:[di+28]
        call    PrintHex32
        call    PrintCRLF
        add     di,32
        ret
PrintPipeDump endp

; ----------------------------------------------------------------------
; Command parser.
; Command: 1 install, 2 dump, 3 clear, 0 invalid.
; ----------------------------------------------------------------------
ParseCommand proc near
        mov     byte ptr cs:[Command],1
        xor     bx,bx
        mov     bl,byte ptr cs:[80h]
        mov     si,81h
PCSkip:
        cmp     bx,0
        je      PCDone
        mov     al,byte ptr cs:[si]
        cmp     al,' '
        je      PCNext
        cmp     al,9
        jne     PCHave
PCNext:
        inc     si
        dec     bx
        jmp     PCSkip
PCHave:
        cmp     al,'/'
        jne     PCInvalid
        inc     si
        mov     al,byte ptr cs:[si]
        and     al,0DFh
        cmp     al,'I'
        je      PCInstall
        cmp     al,'D'
        je      PCDump
        cmp     al,'C'
        je      PCClear
        jmp     short PCInvalid
PCInstall:
        mov     byte ptr cs:[Command],1
        ret
PCDump:
        mov     byte ptr cs:[Command],2
        ret
PCClear:
        mov     byte ptr cs:[Command],3
        ret
PCInvalid:
        mov     byte ptr cs:[Command],0
PCDone:
        ret
ParseCommand endp

Usage:
        mov     dx,offset MsgUsage
        call    PrintZ
        mov     ax,4C01h
        int     21h

; ----------------------------------------------------------------------
; Protected-mode setup.
; ----------------------------------------------------------------------
PrepareProtectedMode proc near
        push    ax
        push    bx
        push    dx
        push    eax

        xor     eax,eax
        mov     ax,cs
        shl     eax,4

        mov     bx,offset GdtCode16
        call    SetDescriptorBase
        mov     bx,offset GdtData16
        call    SetDescriptorBase

        mov     edx,eax
        xor     eax,eax
        mov     ax,offset GdtStart
        add     eax,edx
        mov     dword ptr [Gdtr+2],eax

        mov     ax,cs
        mov     word ptr cs:[ReturnSegment],ax

        pop     eax
        pop     dx
        pop     bx
        pop     ax
        ret
PrepareProtectedMode endp

SetDescriptorBase proc near
        mov     word ptr [bx+2],ax
        ror     eax,16
        mov     byte ptr [bx+4],al
        mov     byte ptr [bx+7],ah
        ror     eax,16
        ret
SetDescriptorBase endp

PciReadDword proc near
        mov     ax,0B10Ah
        xor     bh,bh
        mov     bl,10h
        int     1Ah
        ret
PciReadDword endp

; ----------------------------------------------------------------------
; Printing helpers.
; ----------------------------------------------------------------------
PrintCRLF proc near
        mov     dx,offset MsgCRLF
        call    PrintZ
        ret
PrintCRLF endp

PrintZ proc near
        push    ax
        push    si
        mov     si,dx
PZLoop:
        mov     al,byte ptr cs:[si]
        inc     si
        or      al,al
        jz      PZDone
        mov     dl,al
        call    PutCh
        jmp     PZLoop
PZDone:
        pop     si
        pop     ax
        ret
PrintZ endp

PutCh proc near
        push    ax
        mov     ah,02h
        int     21h
        pop     ax
        ret
PutCh endp

PrintDec16 proc near
        push    ax
        push    bx
        push    cx
        push    dx
        xor     cx,cx
        mov     bx,10
        cmp     ax,0
        jne     PDConvert
        mov     dl,'0'
        call    PutCh
        jmp     short PDDone
PDConvert:
        xor     dx,dx
        div     bx
        push    dx
        inc     cx
        test    ax,ax
        jnz     PDConvert
PDOutput:
        pop     dx
        add     dl,'0'
        call    PutCh
        loop    PDOutput
PDDone:
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
PrintDec16 endp

PrintHex32 proc near
        push    eax
        ror     eax,16
        call    PrintHex16
        ror     eax,16
        call    PrintHex16
        pop     eax
        ret
PrintHex32 endp

PrintHex16 proc near
        push    ax
        mov     al,ah
        call    PrintHex8
        pop     ax
        call    PrintHex8
        ret
PrintHex16 endp

PrintHex8 proc near
        push    ax
        push    bx
        mov     bl,al
        mov     al,bl
        shr     al,4
        call    PrintNibble
        mov     al,bl
        and     al,0Fh
        call    PrintNibble
        pop     bx
        pop     ax
        ret
PrintHex8 endp

PrintNibble proc near
        and     al,0Fh
        cmp     al,9
        jbe     NibbleDigit
        add     al,'A'-10
        jmp     short NibbleOut
NibbleDigit:
        add     al,'0'
NibbleOut:
        mov     dl,al
        call    PutCh
        ret
PrintNibble endp

; ----------------------------------------------------------------------
; Resident data.
; ----------------------------------------------------------------------
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

OldInt10        dd 0
OldInt2F        dd 0
MmioBase        dd 0
XmsEntry        dd 0
SavedFlags      dw 0
CallerSS        dw 0
CallerSP        dw 0
SavedPort70     db 0
Busy            db 0
CurrentPhase    db 0
CurrentKind     db 0
CurrentReqAx    dw 0
CurrentReqBx    dw 0
CurrentBiosAx   dw 0
SnapshotCount   db 0
SnapshotNext    db 0
SequenceCounter dw 0
VmSkipped       dw 0

SnapshotBuffer  db SNAP_COUNT*SNAP_SIZE dup (0)

LocalStack      db 512 dup (0)
LocalStackTop label byte

ResidentEnd label byte

; ----------------------------------------------------------------------
; Transient data/messages. These are still resident in this first diagnostic
; build because /D is executed by a separate program image, not this copy.
; ----------------------------------------------------------------------
Command          db 0
DumpBase         dw 0
DumpSegment      dw 0
DumpCount        dw 0
DumpRecordSize   dw 0
DumpNext         dw 0
DumpSkipped      dw 0
DumpIndex        dw 0

MsgTitle:
        db 13,10,'PFSNAP - T430 read-only display-state snapshot TSR',13,10,0
MsgUsage:
        db 'Usage: PFSNAP [/I | /D | /C]',13,10,0
MsgBar:
        db 'Graphics MMIO BAR0: ',0
MsgInstalled:
        db 'Installed. Run a graphics program, return to DOS, then use PFSNAP /D.',13,10
        db 'Use PFSNAP /C to clear old snapshots.',13,10,0
MsgAlready:
        db 'PFSNAP is already installed.',13,10,0
MsgPciFail:
        db 'PCI BIOS BAR0 read failed.',13,10,0
MsgBarFail:
        db 'Graphics BAR0 is zero.',13,10,0
MsgNoXms:
        db 'HIMEM/XMS is unavailable.',13,10,0
MsgA20Fail:
        db 'XMS could not globally enable A20.',13,10,0
MsgDumpTitle:
        db 13,10,'PFSNAP captured display states',13,10,0
MsgNotInstalled:
        db 'PFSNAP is not installed.',13,10,0
MsgCleared:
        db 'PFSNAP snapshot buffer cleared.',13,10,0
MsgCount:
        db 'Records: ',0
MsgSkipped:
        db '  VM86 captures skipped: ',0
MsgSeparator:
        db 13,10,'------------------------------------------------------------',13,10,0
MsgSequence:
        db 'Sequence ',0
MsgPhase:
        db '  Phase=',0
MsgBefore:
        db 'before',0
MsgAfter:
        db 'after',0
MsgKind:
        db '  Kind=',0
MsgLegacy:
        db 'legacy',0
MsgVbe:
        db 'VBE',0
MsgReqAx:
        db '  ReqAX=',0
MsgReqBx:
        db ' ReqBX=',0
MsgBiosAx:
        db ' BIOSAX=',0
MsgFitterA:
        db 'Fitter A CTL=',0
MsgFitterB:
        db 'Fitter B CTL=',0
MsgFitterC:
        db 'Fitter C CTL=',0
MsgPos:
        db ' POS=',0
MsgSize:
        db ' SIZE=',0
MsgVScale:
        db ' VS=',0
MsgHScale:
        db ' HS=',0
MsgPipeA:
        db 'Pipe A CONF=',0
MsgPipeB:
        db 'Pipe B CONF=',0
MsgPipeC:
        db 'Pipe C CONF=',0
MsgHTotal:
        db ' HTOTAL=',0
MsgHBlank:
        db ' HBLANK=',0
MsgHSync:
        db ' HSYNC=',0
MsgVTotal:
        db ' VTOTAL=',0
MsgVBlank:
        db ' VBLANK=',0
MsgVSync:
        db ' VSYNC=',0
MsgPipeSrc:
        db ' SRC=',0
MsgCRLF:
        db 13,10,0

end start
