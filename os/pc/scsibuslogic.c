/*
 * Buslogic BT-* SCSI Host Adapter in both 24-bit and 32-bit mode.
 * 24-bit mode works for Adaptec 154xx series too.
 *
 * To do:
 *	tidy the PCI probe and do EISA;
 *	allocate more Ccb's as needed, up to NMbox-1;
 *	add nmbox and nccb to Ctlr struct for the above;
 *	64-bit LUN/explicit wide support necessary?
 *
 */
#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "ureg.h"
#include "../port/error.h"

enum {					/* registers */
	Rcontrol	= 0x00,		/* WO: control register */
	Rstatus		= 0x00,		/* RO: status register */
	Rcpr		= 0x01,		/* WO: command/parameter register */
	Rdatain		= 0x01,		/* RO: data-in register */
	Rinterrupt	= 0x02,		/* RO: interrupt register */
};

enum {					/* Rcontrol */
	Rsbus		= 0x10,		/* SCSI Bus Reset */
	Rint		= 0x20,		/* Interrupt Reset */
	Rsoft		= 0x40,		/* Soft Reset */
	Rhard		= 0x80,		/* Hard Reset */
};

enum {					/* Rstatus */
	Cmdinv		= 0x01,		/* Command Invalid */
	Dirrdy		= 0x04,		/* Data In Register Ready */
	Cprbsy		= 0x08,		/* Command/Parameter-Out Register Busy */
	Hardy		= 0x10,		/* Host Adapter Ready */
	Inreq		= 0x20,		/* Initialisation Required */
	Dfail		= 0x40,		/* Diagnostic Failure */
	Dact		= 0x80,		/* Diagnostic Active */
};

enum {					/* Rcpr */
	Cinitialise	= 0x01,		/* Initialise Mailbox */
	Cstart		= 0x02,		/* Start Mailbox Command */
	Cinquiry	= 0x04,		/* Adapter Anquiry */
	Ceombri		= 0x05,		/* Enable OMBR Interrupt */
	Cinquire	= 0x0B,		/* Inquire Configuration */
	Cextbios	= 0x28,		/* AHA-1542: Return extended BIOS information */
	Cmbienable	= 0x29,		/* AHA-1542: Mailbox interface enable */
	Ciem		= 0x81,		/* Initialise Extended Mailbox */
	Ciesi		= 0x8D,		/* Inquire Extended Setup Information */
	Cerrm		= 0x8F,		/* Enable strict round-robin mode */
	Cwide		= 0x96,		/* Wide CCB */
};

enum {					/* Rinterrupt */
	Imbl		= 0x01,		/* Incoming Mailbox Loaded */
	Mbor		= 0x02,		/* Mailbox Out Ready */
	Cmdc		= 0x04,		/* Command Complete */
	Rsts		= 0x08,		/* SCSI Reset State */
	Intv		= 0x80,		/* Interrupt Valid */
};

typedef struct {
	uchar	code;			/* action/completion code */
	uchar	ccb[3];			/* CCB pointer (MSB, ..., LSB) */
} Mbox24;

typedef struct {
	uchar	ccb[4];			/* CCB pointer (LSB, ..., MSB) */
	uchar	btstat;			/* BT-7[45]7[SD] status */
	uchar	sdstat;			/* SCSI device status */
	uchar	pad;
	uchar	code;			/* action/completion code */
} Mbox32;

typedef union {
	Mbox24;
	Mbox32;
} Mbox;

enum {					/* mailbox commands */
	Mbfree		= 0x00,		/* Mailbox not in use */

	Mbostart	= 0x01,		/* Start a mailbox command */
	Mboabort	= 0x02,		/* Abort a mailbox command */

	Mbiok		= 0x01,		/* CCB completed without error */
	Mbiabort	= 0x02,		/* CCB aborted at request of host */
	Mbinx		= 0x03,		/* Aborted CCB not found */
	Mbierror	= 0x04,		/* CCB completed with error */
};

typedef struct Ccb24 Ccb24;
typedef struct Ccb32 Ccb32;
typedef union Ccb Ccb;

typedef struct Ccb24 {
	uchar	opcode;			/* Operation code */
	uchar	datadir;		/* Data direction control */
	uchar	cdblen;			/* Length of CDB */
	uchar	senselen;		/* Length of sense area */
	uchar	datalen[3];		/* Data length (MSB, ..., LSB) */
	uchar	dataptr[3];		/* Data pointer (MSB, ..., LSB) */
	uchar	linkptr[3];		/* Link pointer (MSB, ..., LSB) */
	uchar	linkid;			/* command linking identifier */
	uchar	btstat;			/* BT-* adapter status */
	uchar	sdstat;			/* SCSI device status */
	uchar	reserved[2];		/* */
	uchar	cs[12+0xFF];		/* Command descriptor block + Sense bytes */

	void*	data;			/* buffer if address > 24-bits */

	Rendez;
	int	done;			/* command completed */

	Ccb*	ccb;			/* link on free list */
} Ccb24;


typedef struct Ccb32 {
	uchar	opcode;			/* Operation code */
	uchar	datadir;		/* Data direction control */
	uchar	cdblen;			/* Length of CDB */
	uchar	senselen;		/* Length of sense area */
	uchar	datalen[4];		/* Data length (LSB, ..., MSB) */
	uchar	dataptr[4];		/* Data pointer (LSB, ..., MSB) */
	uchar	reserved[2];
	uchar	btstat;			/* BT-* adapter status */
	uchar	sdstat;			/* SCSI device status */
	uchar	targetid;		/* Target ID */
	uchar	luntag;			/* LUN & tag */
	uchar	cdb[12];		/* Command descriptor block */
	uchar	ccbctl;			/* CCB control */
	uchar	linkid;			/* command linking identifier */
	uchar	linkptr[4];		/* Link pointer (LSB, ..., MSB) */
	uchar	senseptr[4];		/* Sense pointer (LSB, ..., MSB) */
	uchar	sense[0xFF];		/* Sense bytes */

	Rendez;
	int	done;			/* command completed */

	Ccb*	ccb;			/* link on free list */
} Ccb32;

typedef union Ccb {
	Ccb24;
	Ccb32;
} Ccb;

enum {					/* opcode */
	OInitiator	= 0x00,		/* initiator CCB */
	Ordl		= 0x03,		/* initiator CCB with residual data length returned */
};

enum {					/* datadir */
	CCBdatain	= 0x08,		/* inbound data transfer, length is checked */
	CCBdataout	= 0x10,		/* outbound data transfer, length is checked */
};

enum {					/* btstat */
	Eok		= 0x00,		/* CCB completed normally with no errors */
};

enum {					/* luntag */
	TagEnable	= 0x20,		/* Tag enable */
	SQTag		= 0x00,		/* Simple Queue Tag */
	HQTag		= 0x40,		/* Head of Queue Tag */
	OQTag		= 0x80,		/* Ordered Queue Tag */
};

enum {					/* CCB control */
	NoDisc		= 0x08,		/* No disconnect */
	NoUnd		= 0x10,		/* No underrrun error report */
	NoData		= 0x20,		/* No data transfer */
	NoStat		= 0x40,		/* No CCB status if zero */
	NoIntr		= 0x80,		/* No Interrupts */
};

typedef struct {
	ulong	port;			/* I/O port */
	ulong	id;			/* adapter SCSI id */
	int	ctlrno;
	int	bus;			/* 24 or 32 -bit */
	int	spurious;

	Lock	ccblock;
	QLock	ccbq;
	Rendez	ccbr;

	Lock	mboxlock;
	Mbox*	mb;			/* mailbox out + mailbox in */
	int	mbox;			/* current mailbox out index into mb */
	int	mbix;			/* current mailbox in index into mb */

	Lock	cachelock;
	Ccb*	ccb;			/* list of free Ccb's */
	Ccb*	cache[NTarget];		/* last completed Ccb */
} Ctlr;

/*
 * The number of mailboxes should be a multiple of 8 (4 for Mbox32)
 * to ensure the boundary between the out and in mailboxes doesn't
 * straddle a cache-line boundary.
 * The number of Ccb's should be less than the number of mailboxes to
 * ensure no queueing is necessary on mailbox allocation.
 */
enum {
	NMbox		= 8*8,		/* number of Mbox's */
	NCcb		= NMbox-1,	/* number of Ccb's */
};

#define PADDR24(a, n)	(PADDR(a)+n <= (1<<24))

static Ctlr *ctlrxx[MaxScsi];

static void
ccbfree(Ctlr* ctlr, Ccb* ccb)
{
	lock(&ctlr->ccblock);
	if(ctlr->bus == 24)
		((Ccb24*)ccb)->ccb = ctlr->ccb;
	else
		((Ccb32*)ccb)->ccb = ctlr->ccb;
	if(ctlr->ccb == 0)
		wakeup(&ctlr->ccbr);
	ctlr->ccb = ccb;
	unlock(&ctlr->ccblock);
}

static int
ccbavailable(void* a)
{
	return ((Ctlr*)a)->ccb != 0;
}

static Ccb*
ccballoc(Ctlr* ctlr)
{
	Ccb *ccb;

	for(;;){
		lock(&ctlr->ccblock);
		if(ccb = ctlr->ccb){
			if(ctlr->bus == 24)
				 ctlr->ccb = ((Ccb24*)ccb)->ccb;
			else
				 ctlr->ccb = ((Ccb32*)ccb)->ccb;
			unlock(&ctlr->ccblock);
			break;
		}

		unlock(&ctlr->ccblock);
		qlock(&ctlr->ccbq);
		if(waserror()){
			qunlock(&ctlr->ccbq);
			continue;
		}
		sleep(&ctlr->ccbr, ccbavailable, ctlr);
		qunlock(&ctlr->ccbq);
		poperror();
	}

	return ccb;
}

static int
done24(void* arg)
{
	return ((Ccb24*)arg)->done;
}

static int
scsiio24(Target* t, int rw, uchar* cmd, int cbytes, void* data, int* dbytes)
{
	Ctlr *ctlr;
	Ccb24 *ccb;
	Mbox24 *mb;
	ulong p;
	int d, id, n, btstat, sdstat;
	uchar *sense;
	uchar lun;



	if((ctlr = ctlrxx[t->ctlrno]) == 0 || ctlr->port == 0)
		return STharderr;
	id = t->target;
	if(ctlr->id == id)
		return STownid;
	lun = (cmd[1]>>5) & 0x07;

	/*
	 * Ctlr->cache holds the last completed Ccb for this target if it
	 * returned 'check condition'.
	 * If this command is a request-sense and there is valid sense data
	 * from the last completed Ccb, return it immediately.
	 */
	lock(&ctlr->cachelock);
	if(ccb = ctlr->cache[id]){
		ctlr->cache[id] = 0;
		if(cmd[0] == 0x03 && ccb->sdstat == STcheck && lun == ((ccb->cs[1]>>5) & 0x07)){
			unlock(&ctlr->cachelock);
			if(dbytes){
				sense = &ccb->cs[ccb->cdblen];
				n = 8+sense[7];
				if(n > *dbytes)
					n = *dbytes;
				memmove(data, sense, n);
				*dbytes = n;
			}
			ccbfree(ctlr, (Ccb*)ccb);
			return STok;
		}
	}
	unlock(&ctlr->cachelock);
	if(ccb == 0)
		ccb = ccballoc(ctlr);

	/*
	 * Check if the transfer is to memory above the 24-bit limit the
	 * controller can address. If it is, try to allocate a temporary
	 * buffer as a staging area.
	 */
	if(dbytes)
		n = *dbytes;
	else
		n = 0;
	if(n && !PADDR24(data, n)){
		ccb->data = data;
		data = mallocz(n, 0);
		if(data == 0 || !PADDR24(data, n)){
			if(data){
				free(data);
				ccb->data = 0;
			}
			ccbfree(ctlr, (Ccb*)ccb);
			return -1;
		}
		if(rw == SCSIwrite)
			memmove(data, ccb->data, n);
	}

	/*
	 * Fill in the ccb.
	 */
	ccb->opcode = Ordl;

	ccb->datadir = (id<<5)|lun;
	if(n == 0)
		ccb->datadir |= CCBdataout|CCBdatain;
	else if(rw == SCSIread)
		ccb->datadir |= CCBdatain;
	else
		ccb->datadir |= CCBdataout;

	ccb->cdblen = cbytes;
	ccb->senselen = 0xFF;

	ccb->datalen[0] = n>>16;
	ccb->datalen[1] = n>>8;
	ccb->datalen[2] = n;
	p = PADDR(data);
	ccb->dataptr[0] = p>>16;
	ccb->dataptr[1] = p>>8;
	ccb->dataptr[2] = p;

	ccb->linkptr[0] = ccb->linkptr[1] = ccb->linkptr[2] = 0;
	ccb->linkid = 0;
	ccb->btstat = ccb->sdstat = 0;
	ccb->reserved[0] = ccb->reserved[1] = 0;

	memmove(ccb->cs, cmd, cbytes);

	/*
	 * There's one more mbox than there there is
	 * ccb so there is always one free.
	 */
	lock(&ctlr->mboxlock);
	mb = ctlr->mb;
	mb += ctlr->mbox;
	p = PADDR(ccb);
	mb->ccb[0] = p>>16;
	mb->ccb[1] = p>>8;
	mb->ccb[2] = p;
	mb->code = Mbostart;
	ctlr->mbox++;
	if(ctlr->mbox >= NMbox)
		ctlr->mbox = 0;

	/*
	 * This command does not require Hardy
	 * and doesn't generate a Cmdc interrupt.
	 */
	ccb->done = 0;
	outb(ctlr->port+Rcpr, Cstart);
	unlock(&ctlr->mboxlock);

	/*
	 * Wait for the request to complete and return the status.
	 * Since the buffer is not reference counted cannot return
	 * until the DMA is done writing into the buffer so the caller
	 * cannot free the buffer prematurely.
	 */

	while(waserror())
		;

	sleep(ccb, done24, ccb);
	poperror();

	/*
	 * Save the status and patch up the number of
	 * bytes actually transferred.
	 * There's a firmware bug on some 956C controllers
	 * which causes the return count from a successful
	 * READ CAPACITY not be updated, so fix it here.
	 */
	sdstat = ccb->sdstat;
	btstat = ccb->btstat;

	d = ccb->datalen[0]<<16;
	d |= ccb->datalen[1]<<8;
	d |= ccb->datalen[2];
	if(ccb->cs[0] == 0x25 && sdstat == STok)
		d = 0;
	n -= d;
	if(dbytes)
		*dbytes = n;

	/*
	 * Tidy things up if a staging area was used for the data,
	 */
	if(ccb->data){
		if(sdstat == STok && btstat == 0 && rw == SCSIread)
			memmove(ccb->data, data, n);
		free(data);
		ccb->data = 0;
	}

	/*
	 * If there was a check-condition, save the
	 * ccb for a possible request-sense command.
	 */
	if(sdstat == STcheck){
		lock(&ctlr->cachelock);
		if(ctlr->cache[id])
			ccbfree(ctlr, ctlr->cache[id]);
		ctlr->cache[id] = (Ccb*)ccb;
		unlock(&ctlr->cachelock);
		return STcheck;
	}
	ccbfree(ctlr, (Ccb*)ccb);

	if(btstat){
		if(btstat == 0x11)
			return STtimeout;
		return STharderr;
	}
	return sdstat;
}

static void
interrupt24(Ureg*, void* arg)
{
	Ctlr *ctlr;
	ulong port;
	uchar rinterrupt, rstatus;
	Mbox24 *mb, *mbox;
	Ccb24 *ccb;



	ctlr = arg;

	/*
	 * Save and clear the interrupt(s). The only
	 * interrupts expected are Cmdc, which is ignored,
	 * and Imbl which means something completed.
	 * There's one spurious interrupt left over from
	 * initialisation, ignore it.
	 */
	port = ctlr->port;
	rinterrupt = inb(port+Rinterrupt);
	rstatus = inb(port+Rstatus);
	outb(port+Rcontrol, Rint);
	if((rinterrupt & ~(Cmdc|Imbl)) != Intv && ctlr->spurious++)
		print("scsi#%d: interrupt 0x%2.2ux\n", ctlr->ctlrno, rinterrupt);
	if((rinterrupt & Cmdc) && (rstatus & Cmdinv))
		print("scsi#%d: command invalid\n", ctlr->ctlrno);

	/*
	 * Look for something in the mail.
	 * If there is, save the status, free the mailbox
	 * and wakeup whoever.
	 */
	mb = ctlr->mb;
	for(mbox = &mb[ctlr->mbix]; mbox->code; mbox = &mb[ctlr->mbix]){
		ccb = KADDR((mbox->ccb[0]<<16)|(mbox->ccb[1]<<8)|mbox->ccb[2]);
		mbox->code = 0;
		ccb->done = 1;
		wakeup(ccb);

		ctlr->mbix++;
		if(ctlr->mbix >= NMbox+NMbox)
			ctlr->mbix = NMbox;
	}
}


static int
done32(void* arg)
{
	return ((Ccb32*)arg)->done;
}

static int
scsiio32(Target* t, int rw, uchar* cmd, int cbytes, void* data, int* dbytes)
{
	Ctlr *ctlr;
	Ccb32 *ccb;
	Mbox32 *mb;
	ulong p;
	int d, id, n, btstat, sdstat;
	uchar lun;



	if((ctlr = ctlrxx[t->ctlrno]) == 0 || ctlr->port == 0)
		return STharderr;
	id = t->target;
	if(ctlr->id == id)
		return STownid;
	lun = (cmd[1]>>5) & 0x07;

	/*
	 * Ctlr->cache holds the last completed Ccb for this target if it
	 * returned 'check condition'.
	 * If this command is a request-sense and there is valid sense data
	 * from the last completed Ccb, return it immediately.
	 */
	lock(&ctlr->cachelock);
	if(ccb = ctlr->cache[id]){
		ctlr->cache[id] = 0;
		if(cmd[0] == 0x03 && ccb->sdstat == STcheck && lun == (ccb->luntag & 0x07)){
			unlock(&ctlr->cachelock);
			if(dbytes){
				n = 8+ccb->sense[7];
				if(n > *dbytes)
					n = *dbytes;
				memmove(data, ccb->sense, n);
				*dbytes = n;
			}
			ccbfree(ctlr, (Ccb*)ccb);
			return STok;
		}
	}
	unlock(&ctlr->cachelock);
	if(ccb == 0)
		ccb = ccballoc(ctlr);

	/*
	 * Fill in the ccb.
	 */
	ccb->opcode = Ordl;

	if(dbytes)
		n = *dbytes;
	else
		n = 0;
	if(n == 0)
		ccb->datadir |= CCBdataout|CCBdatain;
	else if(rw == SCSIread)
		ccb->datadir |= CCBdatain;
	else
		ccb->datadir |= CCBdataout;

	ccb->cdblen = cbytes;

	ccb->datalen[0] = n;
	ccb->datalen[1] = n>>8;
	ccb->datalen[2] = n>>16;
	ccb->datalen[3] = n>>24;
	p = PADDR(data);
	ccb->dataptr[0] = p;
	ccb->dataptr[1] = p>>8;
	ccb->dataptr[2] = p>>16;
	ccb->dataptr[3] = p>>24;

	ccb->targetid = id;
	ccb->luntag = lun;
	if(t->ok && (t->inq[7] & 0x02))
		ccb->luntag |= SQTag|TagEnable;
	memmove(ccb->cdb, cmd, cbytes);
	ccb->btstat = ccb->sdstat = 0;
	ccb->ccbctl = 0;

	/*
	 * There's one more mbox than there there is
	 * ccb so there is always one free.
	 */
	lock(&ctlr->mboxlock);
	mb = ctlr->mb;
	mb += ctlr->mbox;
	p = PADDR(ccb);
	mb->ccb[0] = p;
	mb->ccb[1] = p>>8;
	mb->ccb[2] = p>>16;
	mb->ccb[3] = p>>24;
	mb->code = Mbostart;
	ctlr->mbox++;
	if(ctlr->mbox >= NMbox)
		ctlr->mbox = 0;

	/*
	 * This command does not require Hardy
	 * and doesn't generate a Cmdc interrupt.
	 */
	ccb->done = 0;
	outb(ctlr->port+Rcpr, Cstart);
	unlock(&ctlr->mboxlock);

	/*
	 * Wait for the request to complete and return the status.
	 * Since the buffer is not reference counted cannot return
	 * until the DMA is done writing into the buffer so the caller
	 * cannot free the buffer prematurely.
	 */
	while(waserror())
		;
	sleep(ccb, done32, ccb);
	poperror();

	/*
	 * Save the status and patch up the number of
	 * bytes actually transferred.
	 * There's a firmware bug on some 956C controllers
	 * which causes the return count from a successful
	 * READ CAPACITY not be updated, so fix it here.
	 */
	sdstat = ccb->sdstat;
	btstat = ccb->btstat;

	d = ccb->datalen[0];
	d |= (ccb->datalen[1]<<8);
	d |= (ccb->datalen[2]<<16);
	d |= (ccb->datalen[3]<<24);
	if(ccb->cdb[0] == 0x25 && sdstat == STok)
		d = 0;
	n -= d;
	if(dbytes)
		*dbytes = n;

	/*
	 * If there was a check-condition, save the
	 * ccb for a possible request-sense command.
	 */
	if(sdstat == STcheck){
		lock(&ctlr->cachelock);
		if(ctlr->cache[id])
			ccbfree(ctlr, ctlr->cache[id]);
		ctlr->cache[id] = (Ccb*)ccb;
		unlock(&ctlr->cachelock);
		return STcheck;
	}
	ccbfree(ctlr, (Ccb*)ccb);

	if(btstat){
		if(btstat == 0x11)
			return STtimeout;
		return STharderr;
	}
	return sdstat;
}

static void
interrupt32(Ureg*, void* arg)
{
	Ctlr *ctlr;
	ulong port;
	uchar rinterrupt, rstatus;
	Mbox32 *mb, *mbox;
	Ccb32 *ccb;

	ctlr = arg;

	/*
	 * Save and clear the interrupt(s). The only
	 * interrupts expected are Cmdc, which is ignored,
	 * and Imbl which means something completed.
	 * There's one spurious interrupt left over from
	 * initialisation, ignore it.
	 */
	port = ctlr->port;
	rinterrupt = inb(port+Rinterrupt);
	rstatus = inb(port+Rstatus);
	outb(port+Rcontrol, Rint);
	if((rinterrupt & ~(Cmdc|Imbl)) != Intv && ctlr->spurious++)
		print("scsi#%d: interrupt 0x%2.2ux\n", ctlr->ctlrno, rinterrupt);
	if((rinterrupt & Cmdc) && (rstatus & Cmdinv))
		print("scsi#%d: command invalid\n", ctlr->ctlrno);

	/*
	 * Look for something in the mail.
	 * If there is, free the mailbox and wakeup whoever.
	 */
	mb = ctlr->mb;
	for(mbox = &mb[ctlr->mbix]; mbox->code; mbox = &mb[ctlr->mbix]){
		ccb = KADDR((mbox->ccb[3]<<24)|(mbox->ccb[2]<<16)|(mbox->ccb[1]<<8)|mbox->ccb[0]);
		mbox->code = 0;
		ccb->done = 1;
		wakeup(ccb);

		ctlr->mbix++;
		if(ctlr->mbix >= NMbox+NMbox)
			ctlr->mbix = NMbox;
	}
}

static Lock cmdlock[MaxScsi];

/*
 * Issue a command to a controller. The command and its length is
 * contained in cmd and cmdlen. If any data is to be
 * returned, datalen should be non-zero, and the returned data
 * will be placed in data.
 * If Cmdc is set, bail out, the invalid command will be handled
 * when the interrupt is processed.
 */
static void
issueio(int port, uchar* cmd, int cmdlen, uchar* data, int datalen)
{
	int len;

	if(cmd[0] != Cstart && cmd[0] != Ceombri){
		while(!(inb(port+Rstatus) & Hardy))
			;
	}
	outb(port+Rcpr, cmd[0]);

	len = 1;
	while(len < cmdlen){
		if(!(inb(port+Rstatus) & Cprbsy)){
			outb(port+Rcpr, cmd[len]);
			len++;
		}
		if(inb(port+Rinterrupt) & Cmdc)
			return;
	}

	if(datalen){
		len = 0;
		while(len < datalen){
			if(inb(port+Rstatus) & Dirrdy){
				data[len] = inb(port+Rdatain);
				len++;
			}
			if(inb(port+Rinterrupt) & Cmdc)
				return;
		}
	}
}

/*
 * Issue a command to a controller, wait for it to complete then
 * reset the interrupt.
 * Should only be called at initialisation.
 */
static int
issue(int ctlrno, int port, uchar* cmd, int cmdlen, uchar* data, int datalen)
{
	uchar rinterrupt, rstatus;

	ilock(&cmdlock[ctlrno]);
	issueio(port, cmd, cmdlen, data, datalen);

	while(!((rinterrupt = inb(port+Rinterrupt)) & Cmdc))
		;

	rstatus = inb(port+Rstatus);
	outb(port+Rcontrol, Rint);
	if((rinterrupt & Cmdc) && (rstatus & Cmdinv)){
		iunlock(&cmdlock[ctlrno]);
		return 0;
	}

	iunlock(&cmdlock[ctlrno]);
	return 1;
}

Scsiio
buslogic24(Ctlr* ctlr, ISAConf* isa)
{
	ulong p;
	Ccb24 *ccb, *ccbp;
	uchar cmd[6], *v;
	int len;

	len = (sizeof(Mbox24)*NMbox*2)+(sizeof(Ccb24)*NCcb);
	v = xspanalloc(len, 32, 0);

	if(!PADDR24(ctlr, sizeof(Ctlr)) || !PADDR24(v, len)){
		print("scsi#%d: %s: 24-bit allocation failed\n",
			ctlr->ctlrno, isa->type);
		return 0;
	}

	ctlr->mb = (Mbox*)v;
	v += sizeof(Mbox24)*NMbox*2;

	ccb = (Ccb24*)v;
	for(ccbp = ccb; ccbp < &ccb[NCcb]; ccbp++){
		ccbp->ccb = ctlr->ccb;
		ctlr->ccb = (Ccb*)ccbp;
	}

	/*
	 * Initialise the software controller and
	 * set the board scanning the mailboxes.
	 */
	ctlr->mbix = NMbox;

	cmd[0] = Cinitialise;
	cmd[1] = NMbox;
	p = PADDR(ctlr->mb);
	cmd[2] = p>>16;
	cmd[3] = p>>8;
	cmd[4] = p;
	len = 5;
	if(issue(ctlr->ctlrno, ctlr->port, cmd, len, 0, 0))
		return scsiio24;

	print("scsi#%d: %s: mbox24 init failed\n", ctlr->ctlrno, isa->type);
	return 0;
}

Scsiio
buslogic32(Ctlr* ctlr, ISAConf* isa)
{
	ulong p;
	Ccb32 *ccb, *ccbp;
	uchar cmd[6], *v;

	v = xspanalloc((sizeof(Mbox32)*NMbox*2)+(sizeof(Ccb32)*NCcb), 32, 0);

	ctlr->mb = (Mbox*)v;
	v += sizeof(Mbox32)*NMbox*2;

	ccb = (Ccb32*)v;
	for(ccbp = ccb; ccbp < &ccb[NCcb]; ccbp++){
		/*
		 * Fill in some stuff that doesn't change.
		 */
		ccbp->senselen = sizeof(ccbp->sense);
		p = PADDR(ccbp->sense);
		ccbp->senseptr[0] = p;
		ccbp->senseptr[1] = p>>8;
		ccbp->senseptr[2] = p>>16;
		ccbp->senseptr[3] = p>>24;

		ccbp->ccb = ctlr->ccb;
		ctlr->ccb = (Ccb*)ccbp;
	}

	/*
	 * Initialise the software controller and
	 * set the board scanning the mailboxes.
	 */
	ctlr->mbix = NMbox;

	cmd[0] = Ciem;
	cmd[1] = NMbox;
	p = PADDR(ctlr->mb);
	cmd[2] = p;
	cmd[3] = p>>8;
	cmd[4] = p>>16;
	cmd[5] = p>>24;
	if(issue(ctlr->ctlrno, ctlr->port, cmd, 6, 0, 0))
		return scsiio32;

	print("scsi#%d: %s: mbox32 init failed\n", ctlr->ctlrno, isa->type);
	return 0;
}

static Pcidev*
buslogicpci(void)
{
	static Pcidev *pcidev;

	pcidev = pcimatch(pcidev, 0x104B, 0);
	return pcidev;
}

static Scsiio
buslogicreset(int ctlrno, ISAConf* isa)
{
	Ctlr *ctlr;
	Pcidev *pcidev;
	uchar cmd[6], data[256];
	int bus, cmdlen, datalen, port, tbdf, timeo;



	pcidev = 0;
	if(isa->port == 0 && (pcidev = buslogicpci()))
		isa->port = pcidev->mem[0].bar & ~0x01;



	if((port = isa->port) == 0)
		return 0;


	/*
	 * Attempt to hard-reset the board and reset
	 * the SCSI bus. If the board state doesn't settle to
	 * idle with mailbox initialisation required, either
	 * it isn't a compatible board or it's broken.
	 * If the controller has SCAM set this can take a while.
	 */
	outb(port+Rcontrol, Rhard|Rsbus);
	for(timeo = 0; timeo < 100; timeo++){
		if(inb(port+Rstatus) == (Inreq|Hardy))
			break;
		delay(100);
	}
	if(inb(port+Rstatus) != (Inreq|Hardy))
		return 0;

	/*
	 * Try to determine if this is a Buslogic 32-bit controller
	 * by attempting to obtain the extended inquiry information;
	 * this command is not implemented on Adaptec 154xx
	 * controllers. If successful, the first byte of the returned
	 * data is the host adapter bus type, 'E' for 32-bit EISA,
	 * PCI and VLB buses.
	 */
	cmd[0] = Ciesi;
	cmd[1] = 4;
	cmdlen = 2;
	datalen = 256;
	bus = 24;
	if(issue(ctlrno, port, cmd, cmdlen, data, datalen)){
		if(data[0] == 'E')
			bus = 32;
	}
	else{
		/*
		 * Inconceivable though it may seem, a hard controller reset is
		 * necessary here to clear out the command queue. Every board seems to
		 * lock-up in a different way if you give an invalid command and then 
		 * try to clear out the command/parameter and/or data-in register.
		 * Soft reset doesn't do the job either. Fortunately no serious
		 * initialisation has been done yet so there's nothing to tidy up.
		 */
		outb(port+Rcontrol, Rhard);
		for(timeo = 0; timeo < 100; timeo++){
			if(inb(port+Rstatus) == (Inreq|Hardy))
				break;
			delay(100);
		}
		if(inb(port+Rstatus) != (Inreq|Hardy))
			return 0;
	}

	/*
	 * If the BIOS is enabled on the 1542C/CF and BIOS options for support of drives
	 * > 1Gb, dynamic scanning of the SCSI bus or more than 2 drives under DOS 5.0
	 * are enabled, the BIOS disables accepting Cmbinit to protect against running
	 * with drivers which don't support those options. In order to unlock the
	 * interface it is necessary to read a lock-code using Cextbios and write it back
	 * using Cmbienable; the lock-code is non-zero.
	 */
	cmd[0] = Cinquiry;
	cmdlen = 1;
	datalen = 4;
	if(issue(ctlrno, port, cmd, cmdlen, data, datalen) == 0){
		print("scsi#%d: %s: Cinquiry\n", ctlrno, isa->type);
		return 0;
	}
	if(data[0] >= 0x43){
		cmd[0] = Cextbios;
		cmdlen = 1;
		datalen = 2;
		if(issue(ctlrno, port, cmd, cmdlen, data, datalen) == 0){
			print("scsi#%d: %s: Cextbios\n", ctlrno, isa->type);
			return 0;
		}

		/*
		 * Lock-code returned in data[1]. If it's non-zero write it back
		 * along with bit 0 of byte 0 cleared to enable mailbox initialisation.
		 */
		if(data[1]){
			cmd[0] = Cmbienable;
			cmd[1] = 0;
			cmd[2] = data[1];
			cmdlen = 3;
			if(issue(ctlrno, port, cmd, cmdlen, 0, 0) == 0){
				print("scsi#%d: %s: Cmbienable\n", ctlrno, isa->type);
				return 0;
			}
		}
	}

	/*
	 * Get the DMA and IRQ info from the board. This will
	 * cause an interrupt which will hopefully not cause any
	 * trouble because the interrupt number isn't known yet.
	 * This is necessary as the DMA won't be set up if the
	 * board has the BIOS disabled.
	 *
	 * This might be a 32-bit card which doesn't have
	 * ISA DMA compatibility set so no DMA channel will show.
	 * Carry on regardless.
	 */
	cmd[0] = Cinquire;
	cmdlen = 1;
	datalen = 3;
	if(issue(ctlrno, port, cmd, cmdlen, data, datalen) == 0){
		print("scsi#%d: %s: can't inquire configuration\n", ctlrno, isa->type);
		return 0;
	}
	switch(data[0]){			/* DMA Arbitration Priority */

	case 0x80:				/* Channel 7 */
		outb(0xD6, 0xC3);
		outb(0xD4, 0x03);
		break;

	case 0x40:				/* Channel 6 */
		outb(0xD6, 0xC2);
		outb(0xD4, 0x02);
		break;

	case 0x20:				/* Channel 5 */
		outb(0xD6, 0xC1);
		outb(0xD4, 0x01);
		break;

	case 0x01:				/* Channel 0 */
		outb(0x0B, 0xC0);
		outb(0x0A, 0x00);
		break;

	default:
		break;
	}

	switch(data[1]){			/* Interrupt Channel */

	case 0x40:
		isa->irq = 15;
		break;

	case 0x20:
		isa->irq = 14;
		break;

	case 0x08:
		isa->irq = 12;
		break;

	case 0x04:
		isa->irq = 11;
		break;

	case 0x02:
		isa->irq = 10;
		break;

	case 0x01:
		isa->irq = 9;
		break;

	default:
		if(pcidev && pcidev->intl){
			isa->irq = pcidev->intl;
			break;
		}

		print("scsi#%d: %s: invalid irq #%2.2ux\n",
			ctlrno, isa->type, data[1]);
		return 0;
	}

	/*
	 * Allocate and start to initialise the software controller.
	 */
	if((ctlr = xalloc(sizeof(Ctlr))) == 0){
		print("scsi#%d: %s: controller allocation failed\n",
			ctlrno, isa->type);
		return 0;
	}
	ctlrxx[ctlrno] = ctlr;

	ctlr->port = isa->port;
	ctlr->id = data[2] & 0x07;
	ctlr->ctlrno = ctlrno;
	ctlr->bus = bus;

	if(bus == 24){
		intrenable(VectorPIC+isa->irq, interrupt24, ctlr, BUSUNKNOWN);
		return buslogic24(ctlr, isa);
	}

	if(pcidev)
		tbdf = pcidev->tbdf;
	else
		tbdf = MKBUS(BusEISA, 0, 0, 0);				/* hack */
	intrenable(VectorPIC+isa->irq, interrupt32, ctlr, tbdf);

	return buslogic32(ctlr, isa);
}

SCSIdev scsibuslogicdev = {
	"buslogic",
	buslogicreset,
};

SCSIdev scsiaha1542dev = {
	"aha1542",
	buslogicreset,
};

void
scsibuslogiclink(void)
{
	addscsilink( &scsiaha1542dev );
}