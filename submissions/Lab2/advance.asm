#INCLUDE <p18f4520.inc>
CONFIG OSC = INTIO67
CONFIG WDT = OFF
org 0x00  

    
setup:
    ;MOVLB 0x2 ;BSR = 2  
; Sequence A 0x01, 0x03, 0x05, 0x07, 0x09, 0x0B
    ;MOVLW 0x01
    ;MOVWF 0x00, 1  ;[0x200]=0x05
    ;MOVLW 0x03
    ;MOVWF 0x01, 1 ;[0x21]=0x1A
    ;MOVLW 0x05
    ;MOVWF 0x02, 1 ;[0x202]=0x2C
    ;MOVLW 0x07
    ;MOVWF 0x03, 1 ;[0x203]=0x40
    ;MOVLW 0x09
    ;MOVWF 0x04, 1 ;[0x204]=0x7E
    ;MOVLW 0x0B
    ;MOVWF 0x05, 1 ;[0x205]=0xA0
; Sequenc B 0x02, 0x04, 0x06, 0x08, 0x0A
    ;MOVLW 0x02
    ;MOVWF 0x10, 1 ;[0x210]=0x01
    ;MOVLW 0x04
    ;MOVWF 0x11, 1 ;[0x211]=0x20
    ;MOVLW 0x06
    ;MOVWF 0x12, 1 ;[0x212]=0x33
    ;MOVLW 0x08
    ;MOVWF 0x13, 1 ;[0x213]=0x80
    ;MOVLW 0x0A
    ;MOVWF 0x14, 1 ;[0x214]=0xF0
    
    LFSR 0, 0x200
    LFSR 1, 0x210
    LFSR 2, 0x220
    
    MOVLW 0x06 ; record A numbers
    MOVWF 0x30, 1
    MOVLW 0x05 ;record B numbers
    MOVWF 0x31, 1
    MOVLW 0x00
    MOVWF 0x40, 1 ;A_counter
    MOVWF 0x41, 1 ;B_counter

start:
    MOVF INDF1, W ;WREG=[FSR1]
    CPFSGT INDF0 ;FSR0(f)>FSR1(w) then skip
    GOTO choose_FSR0 
choose_FSR1:
    MOVF POSTINC1, W ;WREG=[FSR1], FSR1++
    MOVWF POSTINC2 ;[FSR2]=WREG, FSR2++
    INCF 0x241 ;B_counter++
    GOTO endB_check
    
choose_FSR0:
    MOVF POSTINC0, W ;WREG=[FSR0], FSR0++
    MOVWF POSTINC2 ;[FSR2]=WREG, FSR2++
    INCF 0x240 ;A_counter++
    GOTO endA_check

endA_check:
    MOVF 0x40, W, 1 ;WREG=[0x240](A_counter)
    CPFSEQ 0x30, 1 ;A_counter=A_num, skip
    GOTO start
    MOVF 0x41, W, 1 ;WREG=[0x241](B_counter)
    CPFSEQ 0x31, 1 ;B_counter=B_num, skip
    GOTO choose_FSR1
    GOTO ENDDD
    
endB_check:
    MOVF 0x41, W, 1 ;WREG=[0x241](B_counter)
    CPFSEQ 0x31, 1 ;B_counter=B_num, skip
    GOTO start
    MOVF 0x40, W, 1 ;WREG=[0x240](A_counter)
    CPFSEQ 0x30, 1 ;A_counter=A_num, skip
    GOTO choose_FSR0
    GOTO ENDDD

ENDDD:
    NOP
end
    
    


