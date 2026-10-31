#INCLUDE    <p18f4520.inc>
            CONFIG  OSC = INTIO67
            CONFIG  WDT = OFF

; --- Access Bank 暫存 / 緩衝 ---
BUF0        EQU     0x20    ; 0x20..0x27 緩衝 8 筆輸入
A_VAL       EQU     0x28
SWAP_A      EQU     0x29
L_VAL       EQU     0x2A
I_IDX       EQU     0x2B
J_IDX       EQU     0x2C
PAIR_CNT    EQU     0x2D
TMP         EQU     0x2E

            ORG     0x0000

; 0) 清輸出 0x320..0x327
InitOut:
            LFSR    0, 0x0320
            MOVLW   8
            MOVWF   I_IDX
ClrOut:
            CLRF    POSTINC0
            DECFSZ  I_IDX, f
            GOTO    ClrOut

; 1) 複製輸入 0x0000..0x0007 -> BUF0..BUF0+7
CopyIn:
            LFSR    0, 0x0000
            LFSR    1, BUF0
            MOVLW   8
            MOVWF   I_IDX
CopyLoop:
            MOVF    POSTINC0, W
            MOVWF   POSTINC1
            DECFSZ  I_IDX, f
            GOTO    CopyLoop

; 2) 在 BUF 內配對：(A, swap(A)) 共 4 對
;    每對記錄 L=min(A,swap(A)) 到 0x0320..0x0323（待會再排序）
Pairing:
            CLRF    PAIR_CNT            ; 已找到的對數 = 0
            CLRF    I_IDX               ; i = 0
Outer_next_i:
            ; 若 PAIR_CNT == 4 -> 去排序
            MOVF    PAIR_CNT, W
            XORLW   4
            BTFSC   STATUS, Z
            GOTO    SortL

            ; 若 i == 8 -> 結束（理論上不會）
            MOVF    I_IDX, W
            XORLW   8
            BTFSC   STATUS, Z
            GOTO    SortL

            ; FSR0 = BUF0 + i
            LFSR    0, BUF0
            MOVF    I_IDX, W
            ADDWF   FSR0L, f

            ; 取 A = BUF[i]
            MOVF    INDF0, W
            MOVWF   A_VAL

            ; 如果 A 已標 0xFF（用過），i++ 繼續
            MOVF    A_VAL, W
            XORLW   0xFF
            BTFSC   STATUS, Z
            GOTO    Outer_i_inc

            ; 算 SWAP_A
            MOVF    A_VAL, W
            MOVWF   SWAP_A
            SWAPF   SWAP_A, f         ; SWAP_A = swap(A)

            ; 從 j=i+1 開始找 swap(A)
            MOVF    I_IDX, W
            ADDLW   1
            MOVWF   J_IDX

Inner_next_j:
            ; 若 j == 8 -> 沒找到（理論上不會），把 A 標掉，i++ 繼續
            MOVF    J_IDX, W
            XORLW   8
            BTFSC   STATUS, Z
            GOTO    MarkA_and_nextI

            ; FSR1 = BUF0 + j
            LFSR    1, BUF0
            MOVF    J_IDX, W
            ADDWF   FSR1L, f

            ; 若 BUF[j] == 0xFF -> j++ 繼續
            MOVF    INDF1, W
            XORLW   0xFF
            BTFSC   STATUS, Z
            GOTO    Inner_j_inc

            ; 比對是否為 swap(A)
            MOVF    INDF1, W
            CPFSEQ  SWAP_A
            GOTO    Inner_j_inc

            ; --- 找到配對 (i, j) ---
            ; L = min(A, SWAP_A)   <-- 這裡修正了判斷方向
            MOVFF   A_VAL, L_VAL        ; 預設 L = A
            MOVF    A_VAL, W
            CPFSLT  SWAP_A              ; skip if SWAP_A < A
            GOTO    L_ok                ; 若未 skip -> 不需改
            MOVFF   SWAP_A, L_VAL       ; skip 時執行：L = swap(A)
L_ok:
            ; out[PAIR_CNT] = L （寫到 0x0320 + PAIR_CNT）
            LFSR    2, 0x0320
            MOVF    PAIR_CNT, W
            ADDWF   FSR2L, f
            MOVF    L_VAL, W
            MOVWF   INDF2

            ; 把 BUF[i], BUF[j] 標記成 0xFF（避免重複配對）
            MOVLW   0xFF
            MOVWF   INDF0
            MOVWF   INDF1

            ; PAIR_CNT++
            INCF    PAIR_CNT, f

            ; i++ 往下配下一對
            GOTO    Outer_i_inc

Inner_j_inc:
            INCF    J_IDX, f
            GOTO    Inner_next_j

MarkA_and_nextI:
            MOVLW   0xFF
            MOVWF   INDF0            ; 標掉 A（安全起見）
            ; i++ 繼續
Outer_i_inc:
            INCF    I_IDX, f
            GOTO    Outer_next_i

; 3) 將 0x0320..0x0323 的 4 個 L 升冪排序
;    <-- 這裡也修正了比較方向
SortL:
            MOVLW   3
            MOVWF   I_IDX            ; outer = 3
SortL_outer:
            MOVLW   3
            MOVWF   J_IDX            ; inner = 3
            LFSR    0, 0x0320
            LFSR    1, 0x0321
SortL_inner:
            ; 想要「右 < 左 就交換」以達升冪
            MOVF    INDF1, W
            CPFSLT  INDF0            ; skip if 左(INDF0) < 右(W=INDF1)  -> 已有序
            GOTO    SortL_swap       ; 未 skip 表示 左>=右，需要 swap
SortL_noswap:
            INCF    FSR0L, f
            INCF    FSR1L, f
            DECFSZ  J_IDX, f
            GOTO    SortL_inner
            DECFSZ  I_IDX, f
            GOTO    SortL_outer
            GOTO    BuildTail

SortL_swap:
            MOVF    INDF0, W
            MOVFF   INDF1, INDF0
            MOVWF   INDF1
            GOTO    SortL_noswap

; 4) 把 swap(L) 反向寫到 0x0324..0x0327
BuildTail:
            LFSR    0, 0x0320        ; 讀 L (升冪)
            LFSR    1, 0x0327        ; 寫尾端
            MOVLW   4
            MOVWF   I_IDX
TailLoop:
            MOVF    POSTINC0, W
            MOVWF   TMP
            SWAPF   TMP, W
            MOVWF   POSTDEC1
            DECFSZ  I_IDX, f
            GOTO    TailLoop

            GOTO    EndAll

EndAll:
            NOP
            END
