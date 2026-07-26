; SELECTOR.INC
; Shared protected-mode selector values used by T430LCD.
;
; GDT order expected by the current programs:
;   00h null
;   08h 16-bit code
;   10h 16-bit writable data
;   18h flat 4 GiB writable data

SEL_CODE16 equ 08h
SEL_DATA16 equ 10h
SEL_FLAT   equ 18h
