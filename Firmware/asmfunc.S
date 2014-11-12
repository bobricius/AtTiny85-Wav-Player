;---------------------------------------------------------------------------;
; USI controls and Audio output control
;---------------------------------------------------------------------------;

.nolist
#include <avr/io.h>	// Include device specific definitions.
.list

#define	_FLAGS	_SFR_IO_ADDR(GPIOR0)

#ifdef MODE
#if MODE >= 1
#define B_DO	5
#else
#define B_DO	1
#endif
#endif

#define B_CS	3



;---------------------------------------------------------------------------;
; Simple Delay
;---------------------------------------------------------------------------;
; void delay_ms(WORD ms);
; void delay_us(WORD us);

.global delay_ms
.func delay_ms
delay_ms:
	wdr			; Reset WDT
	sbiw	r24, 1		; if (ms-- == 0) return;
	brcs	9f		; /
	ldi	ZL, lo8(F_CPU/4000)	; 1ms delay
	ldi	ZH, hi8(F_CPU/4000)	; 
1:	sbiw	ZL, 1		; 
	brne	1b		; /
	rjmp	delay_ms
9:	ret
.endfunc


.global delay_us
.func delay_us
delay_us:
	ldi	r23, 2
1:	dec	r23
	brne	1b
	sbiw	r24, 1
	brne	delay_us
	wdr
	ret
.endfunc


;---------------------------------------------------------------------------;
; Initialize USI
;
; void init_spi (void);

.global init_spi
.func init_spi
init_spi:
	ldi	r24, 0b00001000			; Enable only SCK and DI. DO is controlled by software
	out	_SFR_IO_ADDR(USICR), r24
	sbi	_SFR_IO_ADDR(PORTB), B_DO	; MMC DI = H
	sbi	_SFR_IO_ADDR(PORTB), B_CS	; MMC CS = H
	ret
.endfunc



;---------------------------------------------------------------------------;
; Control CS
;
; void select (void);
; void deselect (void);

.global select
.func select
select:
	cbi	_SFR_IO_ADDR(PORTB), B_CS	; CS = L
	ret
.endfunc

.global deselect
.func deselect
deselect:
	sbi	_SFR_IO_ADDR(PORTB), B_CS	; CS = H
	ret
.endfunc



;---------------------------------------------------------------------------;
; Receive a byte
;
; BYTE rcv_spi (void);

.global rcv_spi
.func rcv_spi
rcv_spi:
	ldi	r24, 0b000100			;PB2(SCK)
	.rept 16				;Toggle SCK 16 times
	out	_SFR_IO_ADDR(PINB), r24		;
	.endr					;/
	nop					;Read shift register
	in	r24, _SFR_IO_ADDR(USIDR)	;/
	ret
.endfunc



;---------------------------------------------------------------------------;
; Transmit a byte
;
; void xmit_spi (BYTE);

.global xmit_spi
.func xmit_spi
xmit_spi:
	ldi	r25, 0b000100			; PB2(SCK)
	in	r22, _SFR_IO_ADDR(PORTB)

	ldi	r23, 8
1:	bst	r24, 7				;MMC DI = data bit to be sent
	bld	r22, B_DO			;
	out	_SFR_IO_ADDR(PORTB), r22	;
	lsl	r24				;/
	out	_SFR_IO_ADDR(PINB), r25		;SCK = H
	out	_SFR_IO_ADDR(PINB), r25		;SCK = L
	dec	r23				;while(--r23)
	brne	1b				;/

	sbi	_SFR_IO_ADDR(PORTB), B_DO	;MMC DI = H
	ret
.endfunc



;---------------------------------------------------------------------------;
; Read and forward a partial data block
;
; void read_blk_part (void*, WORD, WORD);

.global read_blk_part
.func read_blk_part
read_blk_part:
	movw	XL, r24			;X = R25:R24 (destination memory address)
	movw	ZL, r22			;Z = R23:R22 (byte offset in the sector)

	ldi	r18, lo8(514)		;R19:R18 = 514, Number of bytes to receive
	ldi	r19, hi8(514)		;/
	sub	r18, ZL			;R19:R18 -= Z
	sbc	r19, ZH			;/
	sub	r18, r20		;R19:R18 -= R21:R20
	sbc	r19, r21		;/

	; Skip leading data bytes
	ldi	r24, 0b000100		;PB2(SCK)
1:	sbiw	ZL, 1			;Skip leading data...
	brcs	2f			;
	.rept 16			;Discard a byte on SPI
	out	_SFR_IO_ADDR(PINB), r24	;
	.endr				;/
	rjmp	1b			;
2:	sbiw	XL, 0			;Destination?
	breq	fb_wave

fb_mem:	; Store the data bytes to the memory
	rcall	rcv_spi			;do
	st	X+, r24			; *X++ = rcv_spi()
	subi	r20, 1			;while (--r21:r20)
	sbci	r21, 0			;
	brne	fb_mem			;/
	rjmp	fb_exit

fb_wave: ; Store the data bytes to the audio FIFO
	sbic	_FLAGS, 4		;if (16bit data) R21:R20 /= 2;
	lsr	r21			;
	sbic	_FLAGS, 4		;
	ror	r20			;/
	sbic	_FLAGS, 1		;if (Stereo data) R21:R20 /= 2;
	lsr	r21			;
	sbic	_FLAGS, 1		;
	ror	r20			;/
	lds	r22, FifoWi		;r22 = FIFO write index

3:	ldi	XL, lo8(Buff)		;X = Buff + R22
	ldi	XH, hi8(Buff)		;
	add	XL, r22			;
	adc	XH, r1			;/
4:	lds	r24, FifoCt		;wait while FIFO full
	cpi	r24, 252		;
	brcc	4b			;/
#if MODE >= 1	/* Dual output */
#if MODE >= 2	/* Hi-Res */
	rcall	rcv_spi			;Get L-ch/Mono data into Z
	clr	ZL			;
	sbis	_FLAGS, 4		;
	rjmp	6f			;
	mov	ZL, r24			;
	rcall	rcv_spi			;
	subi	r24, 0x80		;
6:	mov	ZH, r24			;/
	sbis	_FLAGS, 1		;if Mono data, no R-ch data
	rjmp	8f			;/
	rcall	rcv_spi			;Get R-ch data and mix it to Z
	clr	r25			;
	sbis	_FLAGS, 4		;
	rjmp	7f			;
	mov	r25, r24		;
	rcall	rcv_spi			;
	subi	r24, 0x80		;
7:	add	ZL, r25			;
	adc	ZH, r24			;
	ror	ZH			;
	ror	ZL			;/
8:
#if MODE == 3
	mov	ZL, ZH
	com	ZL
#endif
#else		/* Stereo */
	sbic	_FLAGS, 4		;Get L-ch/Mono data into ZH, ZL
	rcall	rcv_spi			;
	rcall	rcv_spi			;
	sbic	_FLAGS, 4		;
	subi	r24, 0x80		;
	mov	ZL, r24			;
	mov	ZH, r24			;/
	sbis	_FLAGS, 1		;if Mono data, do not process R-ch data
	rjmp	9f			;/
	sbic	_FLAGS, 4		;Get R-ch data into ZL
	rcall	rcv_spi			;
	rcall	rcv_spi			;
	sbic	_FLAGS, 4		;
	subi	r24, 0x80		;
	mov	ZL, r24			;/
#endif
9:	st	X+, ZL			;Store Z into FIFO
	st	X+, ZH			;/
	cli				;
	lds	r24, FifoCt		;
	subi	r24, -2			;
	sts	FifoCt, r24		;
	sei				;
	subi	r22, -2			;/
#else		/* Single output */
	sbic	_FLAGS, 4		;Get L-ch/Mono data into ZL
	rcall	rcv_spi			;
	rcall	rcv_spi			;
	sbic	_FLAGS, 4		;
	subi	r24, 0x80		;
	mov	ZL, r24			;/
	sbis	_FLAGS, 1		;if Mono data, do not process R-ch data
	rjmp	9f			;/
	sbic	_FLAGS, 4		;Get R-ch data
	rcall	rcv_spi			;
	rcall	rcv_spi			;
	sbic	_FLAGS, 4		;
	subi	r24, 0x80		;/
	add	ZL, r24			;ZL = (ZL + R-ch) / 2
	ror	ZL			;/
9:	st	X+, ZL			;Store ZL into FIFO
	cli				;
	lds	r24, FifoCt		;
	inc	r24			;
	sts	FifoCt, r24		;
	sei				;
	inc	r22			;/
#endif
	subi	r20, lo8(1)		;while(--R21:R20)
	sbci	r21, hi8(1)		;
	brne	3b			;/
	sts	FifoWi, r22		;Save FIFO write index

fb_exit:	/* Diacard trailing data bytes and CRC */
	ldi	r24, 0b000100		;PB2(SCK)
1:	.rept 16			;Discard a byte on SPI
	out	_SFR_IO_ADDR(PINB), r24	;
	.endr				;/
	subi	r18, lo8(1)		;Repeat r19:r18 times
	sbci	r19, hi8(1)		;
	brne	1b			;/

	ret
.endfunc



;---------------------------------------------------------------------------;
; Audio sampling interrupt process
;
; ISR(TIM0_COMPA_vect);


.global TIM0_COMPA_vect
.func TIM0_COMPA_vect
TIM0_COMPA_vect:
	push	r24				;Save regs.
	in	r24, _SFR_IO_ADDR(SREG)		;
	push	r24				;
	push	ZL				;
	push	ZH				;/

	lds	ZL, FifoRi			;Get FIFO read index
	clr	ZH				;Z = pointer to the top of FIFO
	subi	ZL, lo8(-(Buff))		;
	sbci	ZH, hi8(-(Buff))		;/
	lds	r24, FifoCt			;Load FIFO data counter

#if MODE >= 1	/* Dual output */
	subi	r24, 2				;Check availability of the sampling data
	brcs	9f				;/
	sts	FifoCt, r24			;Save FIFO data counter
	ld	r24, Z+				;Get R-ch/LSB data and send it to PWM
	out	_SFR_IO_ADDR(OCR1A), r24	;/
	ld	r24, Z+				;Get L-ch/MSB data and send it to PWM
	out	_SFR_IO_ADDR(OCR1B), r24	;/
#else		/* Single output */
	subi	r24, 1				;Check availability of the sampling data
	brcs	9f				;/
	sts	FifoCt, r24			;Save FIFO data counter
	ld	r24, Z+				;Send data to PWM
	out	_SFR_IO_ADDR(OCR1B), r24	;/
#endif
	subi	ZL, lo8(Buff)			;Save FIFO read index
	sts	FifoRi, ZL			;/

9:	pop	ZH				;Restore regs.
	pop	ZL				;
	pop	r24				;
	out	_SFR_IO_ADDR(SREG), r24		;
	pop	r24				;/
	reti
.endfunc

