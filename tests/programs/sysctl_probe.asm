; Whole-system boot probe: core/revision detection and the exact SYSCTL OUTW ABI.
; Assemble as a 1.44MB floppy; no DOS installation or writable source image needed.
bits 16
org 0x7c00

    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7c00
    sti
    cld
    mov dx, 0x888a
    mov si, signature
    mov cx, 6
.identify:
    in al, dx
    cmp al, [si]
    jne failed
    inc si
    inc dx
    loop .identify
    mov ax, [0x46c]
    mov [0x602], ax
    mov dx, 0x8888
    mov bp, 0xa180
.speed:
    mov ax, bp
    out dx, ax
    in al, dx
    mov bx, bp
    cmp al, bl
    jne failed
    ; Keep working while BIOS timer interrupts and memory accesses occur.
    mov cx, 35000
.work:
    inc word [0x600]
    loop .work
    inc bp
    cmp bp, 0xa188
    jne .speed
    mov ax, 0xa183                 ; Legacy SYSCTL SYS 56 clears the extension.
    out dx, ax
    in al, dx
    cmp al, 0x83
    jne failed
    mov ax, 0xa100                 ; Legacy SYSCTL MENU restores OSD ownership.
    out dx, ax
    in al, dx
    test al, al
    jnz failed
    mov ax, [0x46c]
    cmp ax, [0x602]                ; IRQ0 must make progress at the slow rates.
    je failed
    mov si, passed_text
    jmp print
failed:
    mov si, failed_text
print:
    lodsb
    test al, al
    jz stopped
    mov ah, 0x0e
    xor bx, bx
    int 0x10
    jmp print
stopped:
    hlt
    jmp stopped

signature: db 'Z486', 1, 0xff
passed_text: db 'SYSCTL_PROBE_OK', 13, 10, 0
failed_text: db 'SYSCTL_PROBE_FAILED', 13, 10, 0
times 510-($-$$) db 0
dw 0xaa55
times 1474560-($-$$) db 0
