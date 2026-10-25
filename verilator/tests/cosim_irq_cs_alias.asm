; Boot-sector regression for IRQ entry with an aliased EIP in a different CS.
; The timer returns to 0000:7D00, but its handler starts at 1000:7D00.
; An EIP-only co-simulator incorrectly executes the foreground CLI first.
bits 16
org 0x7c00

    jmp 0x0000:start
start:
    cli
    xor ax, ax
    mov ds, ax
    mov ss, ax
    mov sp, 0x7000
    mov word [0x7000], ax
    mov ax, 0x1000
    mov es, ax
    mov si, handler
    mov di, 0x7d00
    mov cx, handler_end - handler
    cld
    rep movsb
    mov word [8 * 4], 0x7d00
    mov word [8 * 4 + 2], 0x1000
    mov al, 0xfe
    out 0x21, al
    mov al, 0x34
    out 0x43, al
    xor al, al
    out 0x40, al
    out 0x40, al
    jmp wait_irq

times 0xfe - ($ - $$) db 0x90
wait_irq:
    sti
    hlt
resume:                         ; exactly 0000:7D00
    cli
    cmp word [0x7000], 0x1234
    jne failed
    mov si, success
    jmp print
failed:
    mov si, failure
print:
    lodsb
    test al, al
    jz done
    mov ah, 0x0e
    mov bx, 7
    int 0x10
    jmp print
done:
    cli
    hlt
    jmp done

handler:
    push ax
    mov word [0x7000], 0x1234
    mov al, 0x20
    out 0x20, al
    pop ax
    iret
handler_end:
success: db 'COSIM_IRQ_CS_ALIAS_PASS', 0
failure: db 'COSIM_IRQ_CS_ALIAS_FAIL', 0
times 510 - ($ - $$) db 0
dw 0xaa55
times 1474560 - ($ - $$) db 0
