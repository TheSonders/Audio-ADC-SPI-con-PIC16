;MIT License
;Copyright (c) 2022 Antonio Sánchez (@TheSonders)
;Digitalizador de audio con salida SPI a 3V3 para FPGA
;Usa un PIC16F1933, aunque vale casi cualquiera de la serie 16F19xx
;Muestrea un canal a 76.923Hz y 10 bits de resolución
;Salida por SPI a 2MHz, 2 bytes por muestra (10 bits)
;Para depuración: salida por PWM de 8 bits y 125KHz del audio digitalizado
;Para depuración: salida de 1/4 de frecuencia de reloj por el pin 10
;Agosto 2022

;;;ENCABEZADO;;;
LIST   p=16F1933,r=HEX,w=2
expand
include	"P16F1933.INC"	;Definiciones de registros internos

;;;CONFIGURACIÓN;;;
org  	_IDLOC0 ;Código/Año/Aplic/Version
de	0x13,0x22,0x02,0x01
__config _CONFIG1, _FOSC_INTOSC & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _CP_ON & _CPD_ON & _BOREN_OFF & _CLKOUTEN_ON & _IESO_OFF & _FCMEN_OFF
__config _CONFIG2, _WRT_OFF & _VCAPEN_OFF & _PLLEN_ON & _STVREN_ON & _BORV_HI & _LVP_OFF

;;PATILLAJE DEL PIC;;;
;PORT PIN
;RA0   2   ENTRADA DE AUDIO AN0
;RA1   3    Y AN1 — C12IN1- — — — — — SEG7 — — —
;RA2   4    Y AN2/VREF-— C2IN+/DACOUT— — — — — COM2 — — —
;RA3   5   REFERENCIA POSITIVA ADC (1 Voltio)
;RA4   6   
;RA5   7    Y AN4 CPS7 C2OUT(1) SRNQ(1) — — — SS(1) SEG5 — — VCAP(2)
;RA6  10   SALIDA FOSC/4
;RA7   9    — — — — — — — — — SEG2 — — OSC1/CLKIN
;RB0  21   SALIDA AUDIO PWM (CCP4)
;RB1  22    Y AN10 CPS1 C12IN3- — — P1C — — VLCD1 IOC Y —
;RB2  23    Y AN8 CPS2 — — — P1B — — VLCD2 IOC Y —
;RB3  24    Y AN9 CPS3 C12IN2- — — CCP2(1)/P2A(1)— — VLCD3 IOC Y —
;RB4  25    Y AN11 CPS4 — — — P1D — — COM0 IOC Y —
;RB5  26    Y AN13 CPS5 — — T1G(1) P2B(1)CCP3(1)/P3A(1)— — COM1 IOC Y —
;RB6  27    — — — — — — — — — SEG14 IOC Y ICSPCLK/ICDCLK
;RB7  28    — — — — — — — — — SEG13 IOC Y ICSPDAT/ICDDAT
;RC0  11    — — — — — T1OSO/T1CKIP2B(1) — — — — — —
;RC1  12    — — — — — T1OSI CCP2(1)/P2A(1)— — — — — —
;RC2  13    — — — — — — CCP1/P1A— — SEG3 — — —
;RC3  14   SPI CLOCK
;RC4  15    — — — — — T1G(1) — — SDI/SDA SEG11 — — —
;RC5  16   SPI DATA
;RC6  17    — — — — — — CCP3(1)P3A(1)TX/CK — SEG9 — — —
;RC7  18    — — — — — — P3B RX/DT — SEG8 — — —
;RE3   1    — — — — — — — — — — — Y MCLR/VPP
;VDD  20    — — — — — — — — — — — — VDD
;Vss  8,19  — — — — — — — — — — — — VSS

;;;MACROS;;;
MOVLWF	macro literal,file	
	movlw	literal
	movwf	file
	ENDM

MOVFWF	macro	source,dest
	movf	source,W
	movwf	dest
	ENDM

RESULTH	equ	.112		;Variables temporales
RESULTL	equ	.113
MASK	equ	b'00000101'	;Máscara de alineación

;;;RESET;;;
ORG 0x0000
	goto Inicio

;;;RUTINA DE INTERRUPCIÓN;;;
ORG 0x0004
ISR:
	banksel ADRESL		;En cada interrupción...
	bsf	ADCON0,GO	;...activamos de nuevo del ADC
	MOVFWF	ADRESL,RESULTL	;Copiamos los valores en RESULT
	MOVFWF	ADRESH,RESULTH
	banksel	SSPBUF		;Transmitimos por SPI el byte alto
	movwf	SSPBUF
	banksel	CCPR4L		;Copiamos los dos bits bajos al PWM
	lsrf	RESULTH		
	bcf	CCP4CON,4	;El PWM lo tenemos a 8 bits
	btfsc	STATUS,C	;Sólo usamos RESULTH para el PWM
	bsf	CCP4CON,4
	lsrf	RESULTH
	bcf	CCP4CON,5
	btfsc	STATUS,C	;RESULTH ya no lo necesitamos		
	bsf	CCP4CON,5
	MOVFWF	RESULTH,CCPR4L	;Copiamos los 6 bits altos al PWM
	banksel	SSPBUF		
	movlw	MASK		;Cargamos la máscara de alineación...
	iorwf	RESULTL,F	;...del byte bajo
	movf	RESULTL,W
	btfss	SSPSTAT,BF	;Esperamos que el byte alto se transmita
	goto	$-.1
	movwf	SSPBUF		;Transmitimos por SPI el byte bajo
	banksel PIR1
	bcf	PIR1,TMR2IF	;Limpiamos la interrupción y volvemos
	retfie

;;;INICIO DEL PROGRAMA;;;
Inicio:
	banksel OSCCON
	MOVLWF	b'11110000',OSCCON 	;32MHz usando PLL interno
	banksel TRISB			;Los pines No usados los ponemos como entrada
	MOVLWF	b'11111110',TRISB	;Se aconseja que dichos pines se unan a GND
	MOVLWF	b'11010111',TRISC
	banksel	ANSELA			;Dos entradas analógicas:
	MOVLWF	b'00001001',ANSELA	; la del audio y la referencia positiva
	banksel	ADCON0
	MOVLWF	b'00000001',ADCON0	;AN0
	MOVLWF	b'00100010',ADCON1	;VREF+ EXTERNO
	banksel SSPCON1
	MOVLWF	b'00100001',SSPCON1	;SPI FOSC/16
	banksel PIE1
	bsf	PIE1,TMR2IE		;Interrupción del TMR2 habilitada
	banksel	INTCON
	MOVLWF	b'11000000',INTCON
	banksel	CCP4CON			;Usamos el módulo PWM4
	MOVLWF	b'00001100',CCP4CON
	banksel	CCPTMRS0
	MOVLWF	b'01000000',CCPTMRS0	;CCP4 TMR4
	banksel T4CON
	MOVLWF	.63,PR4			;32MHz/256=125.000Hz PWM
	MOVLWF	b'00000100',T4CON	
	banksel T2CON			;8MHz/104=76.923Hz sampleo
	MOVLWF	.103,PR2		;13us por muestra	
	MOVLWF	b'00000100',T2CON
loop:
	goto loop
	
end