/*
 * Can't write 16-bit code for 8a without getting into
 * lots of bother, so define some simple commands and
 * output the code directly.
 */
#define rAX		0		/* rX  */
#define rCX		1
#define rDX		2
#define rBX		3
#define rSP		4		/* SP */
#define rBP		5		/* BP */
#define rSI		6		/* SI */
#define rDI		7		/* DI */

#define rAL		0		/* rL  */
#define rCL		1
#define rDL		2
#define rBL		3
#define rAH		4		/* rH */
#define rCH		5
#define rDH		6
#define rBH		7

#define rES		0		/* rS */
#define rCS		1
#define rSS		2
#define rDS		3
#define rFS		4
#define rGS		5

#define xBPaDI		3
#define xSI		4		/* rI (index) */
#define xDI		5
#define xBP		6
#define xBX		7

#define rCR0		0		/* rC */
#define rCR2		2
#define rCR3		3
#define rCR4		4

#define OP(o, m, r, rm)	BYTE $o;		/* op + modr/m byte */	\
			BYTE $((m<<6)|(r<<3)|rm)
#define OPrm(o, r, m)	OP(o, 0x00, r, 0x06);	/* general r <-> m */	\
			WORD $m;
#define OPrr(o, r0, r1)	OP(o, 0x03, r0, r1);	/* general r -> r */

#define LW(m, rX)	OPrm(0x8B, rX, m)	/* m -> rX */
#define LXW(x, rI, r)	OP(0x8B, 0x02, r, rI);	/* x(rI) -> r */	\
			WORD $x
#define LBPW(x, r)	OP(0x8B, 0x02, r, 0x06);/* x(rBP) -> r */	\
			WORD $x
#define LB(m, rB)	OPrm(0x8A, rB, m)	/* m -> r[HL] */
#define LXB(x, rI, r)	OP(0x8A, 0x01, r, rI);	/* x(rI) -> r */	\
			BYTE $x
#define LBPB(x, r)	OP(0x8A, 0x01, r, 0x06);/* x(rBP) -> r */	\
			BYTE $x
#define SW(rX, m)	OPrm(0x89, rX, m)	/* rX -> m */
#define SXW(r, x, rI)	OP(0x89, 0x02, r, rI);	/* r -> x(rI) */	\
			WORD $x
#define SBPW(r, x)	OP(0x89, 0x02, r, 0x06);/* r -> x(rBP) */	\
			WORD $x
#define STB(rB, m)	OPrm(0x88, rB, m)	/* rB -> m */
#define SXB(r, x, rI)	OP(0x88, 0x01, r, rI);	/* rB -> x(rI) */	\
			BYTE $x
#define SBPB(r, x)	OP(0x88, 0x01, r, 0x06);/* r -> x(rBP) */	\
			BYTE $x
#define LWI(i, rX)	BYTE $(0xB8+rX);	/* i -> rX */		\
			WORD $i;
#define LBI(i, rB)	BYTE $(0xB0+rB);	/* i -> r[HL] */	\
			BYTE $i

#define MW(r0, r1)	OPrr(0x89, r0, r1)	/* r0 -> r1 */
#define MFSR(rS, rX)	OPrr(0x8C, rS, rX)	/* rS -> rX */
#define MTSR(rX, rS)	OPrr(0x8E, rS, rX)	/* rX -> rS */
#define MFCR(rC, rX)	BYTE $0x0F;		/* rC -> rX */		\
			OP(0x20, 0x03, rC, rX)
#define MTCR(rX, rC)	BYTE $0x0F;		/* rX -> rC */		\
			OP(0x22, 0x03, rC, rX)

#define ADC(r0, r1)	OPrr(0x11, r0, r1)	/* r0 + r1 -> r1 */
#define ADD(r0, r1)	OPrr(0x01, r0, r1)	/* r0 + r1 -> r1 */
#define ADDI(i, r)	OP(0x81, 0x03, 0x00, r);/* i+r -> r */		\
			WORD $i;
#define AND(r0, r1)	OPrr(0x21, r0, r1)	/* r0&r1 -> r1 */
#define ANDI(i, r)	OP(0x81, 0x03, 0x04, r);/* i&r -> r */		\
			WORD $i;
#define CLR(r)		OPrr(0x31, r, r)	/* r^r -> r */
#define CLRB(r)		OPrr(0x30, r, r)	/* r^r -> r */
#define CMP(r0, r1)	OPrr(0x39, r0, r1)	/* r1-r0 -> flags */
#define CMPI(i, r)	OP(0x81, 0x03, 0x07, r);/* r-i -> flags */	\
			WORD $i;
#define CMPB(r0, r1)	OPrr(0x38, r0, r1)	/* r1-r0 -> flags */
#define CMPBI(i, r)	OP(0x80, 0x03, 0x07, r);/* r-i -> flags */	\
			BYTE $(i);
#define DEC(r)		BYTE $(0x48|r)		/* r-1 -> r */
#define DIV(r)		OPrr(0xF7, 0x06, r)	/* rAX/r -> rDX:rAX */
#define INC(r)		BYTE $(0x40|r)		/* r+1 -> r */
#define MUL(r)		OPrr(0xF7, 0x04, r)	/* r*rAX -> rDX:rAX */
#define OR(r0, r1)	OPrr(0x09, r0, r1)	/* r0|r1 -> r1 */
#define ORB(r0, r1)	OPrr(0x08, r0, r1)	/* r0|r1 -> r1 */
#define ORI(i, r)	OP(0x81, 0x03, 0x01, r);/* i|r -> r */		\
			WORD $i;
#define ROLI(i, r)	OPrr(0xC1, 0x00, r);	/* r<<>>i -> r */	\
			BYTE $i;
#define SHLI(i, r)	OPrr(0xC1, 0x04, r);	/* r<<i -> r */		\
			BYTE $i;
#define SHLBI(i, r)	OPrr(0xC0, 0x04, r);	/* r<<i -> r */		\
			BYTE $i;
#define SUB(r0, r1)	OPrr(0x29, r0, r1)	/* r1-r0 -> r1 */
#define SUBI(i, r)	OP(0x81, 0x03, 0x05, r);/* r-i -> r */		\
			WORD $i;

#define CALL(f)		LWI(f, rDI);		/* &f -> rDI */		\
			BYTE $0xFF;		/* (*rDI) */		\
			BYTE $0xD7;
#define FARJUMP16(s, o)	BYTE $0xEA;		/* jump to ptr16:16 */	\
			WORD $o; WORD $s
#define FARJUMP32(s, o)	BYTE $0x66;		/* jump to ptr32:16 */	\
			BYTE $0xEA; LONG $o; WORD $s
#define	DELAY		BYTE $0xEB;		/* jmp .+2 */		\
			BYTE $0x00
#define SYSCALL(b)	INT $b			/* INT $b */

#define POKEW		BYTE $0x26;		/* MOVW	rAX, rES:[rBX] */	\
			BYTE $0x89; BYTE $0x07
#define PEEKW		BYTE	$0x26;		/* MOVW rES:[rBX], rAX */	\
			BYTE $0x8b; BYTE $0x07
#define OUTPORTB(p, d)	LBI(d, rAL);		/* d -> I/O port p */	\
			BYTE $0xE6;					\
			BYTE $p; DELAY
#define PUSHA		BYTE $0x60
#define PUSHW(r)	BYTE $(0x50|r)		/* r  -> (--rSP) */
#define PUSHDS	BYTE	$0x1E
#define PUSHES	BYTE  $0x06
#define POPA		BYTE $0x61
#define POPW(r)		BYTE $(0x58|r)		/* (rSP++) -> r */
#define POPDS		BYTE $0x1F
#define POPES		BYTE	$0x07
#define NOP		BYTE $0x90		/* nop */

/*
 * Some MMU stuff.
 */
#define SELGDT		(0<<3)			/* selector is in gdt */
#define	SELLDT		(1<<3)			/* selector is in ldt */

#define SELECTOR(i, t, p)	(((i)<<3) | (t) | (p))

#define LGDT(gdtptr)	BYTE $0x0F;		/* LGDT */			\
			BYTE $0x01; BYTE $0x16;					\
			WORD $gdtptr

#define SEGDATA	(0x10<<8)	/* data/stack segment */
#define SEGEXEC	(0x18<<8)	/* executable segment */
#define SEGTSS	(0x9<<8)	/* TSS segment */
#define SEGCG	(0x0C<<8)	/* call gate */
#define SEGIG	(0x0E<<8)	/* interrupt gate */
#define SEGTG	(0x0F<<8)	/* task gate */
#define SEGTYPE	(0x1F<<8)

#define SEGP	(1<<15)		/* segment present */
#define SEGPL(x) ((x)<<13)	/* priority level */
#define SEGB	(1<<22)		/* granularity 1==4k (for expand-down) */
#define SEGG	(1<<23)		/* granularity 1==4k (for other) */
#define SEGE	(1<<10)		/* expand down */
#define SEGW	(1<<9)		/* writable (for data/stack) */
#define	SEGR	(1<<9)		/* readable (for code) */
#define SEGD	(1<<22)		/* default 1==32bit (for code) */


#define KZERO	0x80000000
