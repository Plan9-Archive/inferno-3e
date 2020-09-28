#include "../port/portfns.h"

ulong	aifinit(uchar *aifarr);
void	aamloop(int);
void	archconfinit(void);
int	archflash12v(int);
void	archflashwp(int);
int	archhooksw(int);
void	archreboot(void);
void	archreset(void);
void	archspeaker(int, int);
void	archrdtsc(vlong *);
ulong archrdtsc32(void);
int	archtadcodecsok(void);
char* bpgetenv(char*);
char* bpenumenv(int);
int	bpoverride(char*, int*);
int	bpoverride_uchar(char*, uchar*);
ulong	call_apcs(ulong addr, int nargs, ...);
ulong	call_apcs0(ulong addr);
ulong	call_apcs1(ulong addr, ulong a1);
ulong	call_apcs2(ulong addr, ulong a1, ulong a2);
ulong	call_apcs3(ulong addr, ulong a1, ulong a2, ulong a3);
void	catchDref(char *s, void *v);
void	catchDval(char *s, ulong v, ulong m);
void	catchIref(char *s, void *a);
void	cisread(int slotno, void (*f)(int, uchar *));
int	cistrcmp(char *, char *);
void	cleanDentry(void *);
void	clockcheck(void);
void	clockinit(void);
void	clockpoll(void);
#define	coherence()		/* nothing to do for cache coherence for uniprocessor */
uint	cpsrr(void);
void	cursorhide(void);
void	cursorunhide(void);
void	dmasetup(int channel, int device, int direction, int endianess);
void	dmastart(int channel, void *b1, int b1siz, void *b2, int b2siz);
int	dmacontinue(int channel, void *buf, int bufsize);
void	dmastop(int channel);
int	dmaerror(int channel);
void	dmareset(void);
void	drainWBuffer(void);
void dumplongs(char *, ulong *, int);
void	dumpregs(Ureg* ureg);
void	dumpstk(ulong *);
void	flushDcache(void);
void	flushIDC(void);
void	flushIcache(void);
void	flushDentry(void *);
void	flushTLB(void);
int	fpiarm(Ureg*);
void	fpinit(void);
ulong	getcallerpc(void*);
void	gotopc(ulong);
#define	idlehands()			/* nothing to do in the runproc */
void	intrenable(int, void (*)(Ureg*, void*), void*, int);
int	iprint(char *fmt, ...);
void	installprof(void (*)(Ureg *, int));
int	isvalid_pc(ulong);
int	isvalid_va(void*);
void	kbdinit(void);
void	lcd_setbacklight(int);
void	lcd_setbrightness(ushort);
void	lcd_setcontrast(ushort);
void	lcd_sethz(int);
void	lights(ulong);
void	links(void);
ulong	mcpgettfreq(void);
void	mcpinit(void);
void	mcpsettfreq(ulong tfreq);
void	mcpspeaker(int, int);
void	mcptelecomsetup(ulong hz, uchar adm, uchar xint, uchar rint);
ushort	mcpadcread(int ts);
void	mcptouchsetup(int ts);
void	mcptouchintrenable(void);
void	mcptouchintrdisable(void);
void	mcpgpiowrite(ushort mask, ushort data);
void	mcpgpiosetdir(ushort mask, ushort dir);
ushort	mcpgpioread(void);
void	mmuinit(void);
ulong	mmuctlregr(void);
void	mmuctlregw(ulong);
ulong	mmuregr(int);
void	mmuregw(int, ulong);
void	mmureset(void);
void	mouseinit(void);
void	nowriteSeg(void *, void *);
void*	pa2va(ulong);
int	pcmpin(int slot, int type);
void	pcmpower(int slotno, int on);
int	pcmpowered(int slotno);
void	pcmsetvcc(int slotno, int vcc);
void	pcmsetvpp(int slotno, int vpp);
int	pcmspecial(char *idstr, ISAConf *isa);
void	pcmspecialclose(int slotno);
void	pcmintrenable(int, void (*)(Ureg*, void*), void*);
void	putcsr(ulong);
#define procsave(p)
#define procrestore(p)
void	remaplomem(void);
long	rtctime(void);
void*	screenalloc(ulong);
void	screeninit(void);
void	screenputs(char*, int);
int	segflush(void*, ulong);
void	setpanic(void);
void	setr13(int, void*);
uint	spsrr(void);
void	touchrawcal(int q, int px, int py);
int	touchcalibrate(void);
int	touchreadxy(int *fx, int *fy);
int	touchpressed(void);
int	touchreleased(void);
void	touchsetrawcal(int q, int n, int v);
int	touchgetrawcal(int q, int n);
void	trapinit(void);
void	trapspecial(int (*)(Ureg *, uint));
int	uartprint(char*, ...);
void	uartspecial(int, int, char, Queue**, Queue**, int (*)(Queue*, int));
void	umbfree(ulong addr, int size);
ulong	umbmalloc(ulong addr, int size, int align);
void	umbscan(void);
ulong	va2pa(void*);
void	vectors(void);
void	vtable(void);
#define	waserror()	(up->nerrlab++, setlabel(&up->errlab[up->nerrlab-1]))
int	wasbusy(int);
void	_vfiqcall(void);
void	_virqcall(void);
void	_vundcall(void);
void	_vsvccall(void);
void	_vpabcall(void);
void	_vdabcall(void);
void	vgaputc(char);
void	writeBackBDC(void);
void	writeBackDC(void);

#define KADDR(p)	((void *) p)
#define PADDR(v)	va2pa((void*)(v))

// #define timer_start()	(*OSCR)
// #define timer_ticks(t)	(*OSCR - (ulong)(t))
#define DELAY(ms)	timer_delay(MS2TMR(ms))
#define MICRODELAY(us)	timer_delay(US2TMR(us))
ulong	timer_start(void);
ulong	timer_ticks(ulong);
int 	timer_devwait(ulong *adr, ulong mask, ulong val, int ost);
void 	timer_setwatchdog(int ost);
void 	timer_delay(int ost);
ulong	ms2tmr(int ms);
int	tmr2ms(ulong t);
void	delay(int ms);
ulong	us2tmr(int us);
int	tmr2us(ulong t);
void 	microdelay(int us);
