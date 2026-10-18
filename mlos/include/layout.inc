; Internal S00-S02 layout. 512 KiB installed; never use expansion maximum.
FRAME_COUNT     equ 32
FRAME_SIZE      equ $4000
CORE_FRAME      equ 0
COMMON_FRAME    equ 1
DISCARD_FRAME   equ 2
APP_FRAME       equ 3
CORE_START      equ $0000
CORE_DISPATCH   equ $0003
APP_START       equ $0400
APP_STACK       equ $3E00

; Hardware full native frame: V and MD are NOT hardware stacked.
N_CC            equ 0
N_A             equ 1
N_B             equ 2
N_E             equ 3
N_F             equ 4
N_DP            equ 5
N_X             equ 6
N_Y             equ 8
N_U             equ 10
N_PC            equ 12
N_SIZE          equ 14

ENTRY_DEPTH     equ $C000
ENTRY_REASON    equ $C001
PANIC_REASON    equ $C002
NMI_GUARD       equ $C003
IRQ_COUNT       equ $C004
TRAP_COUNT      equ $C006
TEST_RESULT     equ $C008
TEST_STEP       equ $C009
UART_IMR_SHADOW equ $C00A
UART_ACR_SHADOW equ $C00B
ENTRY_BASE      equ $C020
ENTRY_SIZE      equ 32
ENTRY_MAX       equ 4
R_S             equ 14
R_V             equ 16
R_MAP           equ 18
R_REASON        equ 21
R_PRIV          equ 22
REASON_CALL     equ 0
REASON_IRQ      equ 1
REASON_TRAP     equ 2
REASON_NESTED   equ 3

CURRENT_PID     equ $C100
PROCESS_MAP     equ $C102
PROCESS_ROLE    equ $C105
ROLE_VACANT     equ 0
ROLE_RESIDENT   equ 1
ROLE_RESOURCE   equ 2
FREE_COUNT      equ $C108
ALLOC_FAIL_AFTER equ $C109
FRAME_TABLE     equ $C200
FRAME_RECORD_SIZE equ 8
F_OWNER         equ 0             ; u16, zero free; $FFFF reserved
F_FLAGS         equ 2
F_REFS          equ 3
F_PINS          equ 4
F_RESERVED      equ 1
F_RESIDENT      equ 2
F_PROVISIONAL   equ 4
    ifdef MLOS_RUNTIME
    include "scheduling.inc"
HANDLE_TABLE equ $3800
HANDLE_COUNT equ 64
    else
HANDLE_TABLE    equ $C300
HANDLE_COUNT    equ 32
    endc
HANDLE_RECORD_SIZE equ 8
H_OWNER         equ 0             ; u16
H_GEN           equ 2             ; u8; never wraps; exhausted slots retire
H_FRAME         equ 3
H_LIVE          equ 4
H_REFS          equ 5
H_PINS          equ 6
H_RETIRED       equ 7
PARAM_BUFFER    equ $C400         ; 16 bytes
COPY_BUFFER     equ $C410         ; 256 byte snapshot, SYS_COPY all-or-nothing
ALLOC_LIST      equ $C510         ; 29 frame IDs, provisional transaction
ALLOC_COUNT     equ $C52D
COPY_ADDRESS    equ $C530
COPY_LENGTH     equ $C532
COPY_DEST       equ $C534
COPY_DIRECTION  equ $C536
COPY_SAVED_MAP  equ $C537
COPY_END        equ $C538
LOOKUP_TOKEN    equ $C53A
LOOKUP_INDEX    equ $C53C
TEMP_HANDLE     equ $C53E
SC_RESULT       equ $C540
    ifdef MLOS_RUNTIME
KERNEL_CANARY equ $C800
KERNEL_STACK equ $CC00
EMERGENCY_CANARY equ $CC00
EMERGENCY_STACK equ $CD00
COMMON_USED_END equ $E000
    else
KERNEL_CANARY   equ $C800
KERNEL_STACK    equ $D000         ; $C802-$CFFF, 2046 bytes
EMERGENCY_CANARY equ $D000
EMERGENCY_STACK equ $D200         ; 510 bytes
COMMON_USED_END equ $D200
    endc
