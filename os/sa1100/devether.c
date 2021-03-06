#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "io.h"
#include "ureg.h"
#include "../port/error.h"
#include "../port/netif.h"

#include "etherif.h"

int
cistrcmp(char *a, char *b)
{
	int ac, bc;

	for(;;){
		ac = *a++;
		bc = *b++;
	
		if(ac >= 'A' && ac <= 'Z')
			ac = 'a' + (ac - 'A');
		if(bc >= 'A' && bc <= 'Z')
			bc = 'a' + (bc - 'A');
		ac -= bc;
		if(ac)
			return ac;
		if(bc == 0)
			break;
	}
	return 0;
}

void ethermediumlink(void);

static Ether *etherxx[MaxEther];

Chan*
etherattach(char* spec)
{
	ulong ctlrno;
	char *p;
	Chan *chan;

	ctlrno = 0;
	if(spec && *spec){
		ctlrno = strtoul(spec, &p, 0);
		if((ctlrno == 0 && p == spec) || *p || (ctlrno >= MaxEther))
			error(Ebadarg);
	}
	if(etherxx[ctlrno] == 0)
		error(Enodev);

	chan = devattach('l', spec);
	chan->dev = ctlrno;
	if(etherxx[ctlrno]->attach)
		etherxx[ctlrno]->attach(etherxx[ctlrno]);
	return chan;
}

static int
etherwalk(Chan* chan, char* name)
{
	return netifwalk(etherxx[chan->dev], chan, name);
}

static void
etherstat(Chan* chan, char* dp)
{
	netifstat(etherxx[chan->dev], chan, dp);
}

static Chan*
etheropen(Chan* chan, int omode)
{
	return netifopen(etherxx[chan->dev], chan, omode);
}

static void
ethercreate(Chan*, char*, int, ulong)
{
}

static void
etherclose(Chan* chan)
{
	netifclose(etherxx[chan->dev], chan);
}

static long
etherread(Chan* chan, void* buf, long n, ulong offset)
{
	Ether *ether;

	ether = etherxx[chan->dev];
	if((chan->qid.path & CHDIR) == 0 && ether->ifstat){
		/*
		 * With some controllers it is necessary to reach
		 * into the chip to extract statistics.
		 */
		if(NETTYPE(chan->qid.path) == Nifstatqid)
			return ether->ifstat(ether, buf, n, offset);
		else if(NETTYPE(chan->qid.path) == Nstatqid)
			ether->ifstat(ether, buf, 0, offset);
	}

	return netifread(ether, chan, buf, n, offset);
}

static Block*
etherbread(Chan* chan, long n, ulong offset)
{
	return netifbread(etherxx[chan->dev], chan, n, offset);
}

static void
etherremove(Chan*)
{
}

static void
etherwstat(Chan* chan, char* dp)
{
	netifwstat(etherxx[chan->dev], chan, dp);
}

static void
etherrtrace(Netfile* f, Etherpkt* pkt, int len)
{
	int i, n;
	Block *bp;

	if(qwindow(f->in) <= 0)
		return;
	if(len > 58)
		n = 58;
	else
		n = len;
	bp = iallocb(64);
	if(bp == 0)
		return;
	memmove(bp->wp, pkt->d, n);
	i = TK2MS(m->ticks);
	bp->wp[58] = len>>8;
	bp->wp[59] = len;
	bp->wp[60] = i>>24;
	bp->wp[61] = i>>16;
	bp->wp[62] = i>>8;
	bp->wp[63] = i;
	bp->wp += 64;
	qpass(f->in, bp);
}

Block*
etheriq(Ether* ether, Block* bp, int freebp)
{
	Etherpkt *pkt;
	ushort type;
	int len;
	Netfile **ep, *f, **fp, *fx;
	Block *xbp;

	ether->inpackets++;

	pkt = (Etherpkt*)bp->rp;
	len = BLEN(bp);
	type = (pkt->type[0]<<8)|pkt->type[1];
	fx = 0;
	ep = &ether->f[Ntypes];

	/* check for valid multcast addresses */
	if((pkt->d[0] & 1) && memcmp(pkt->d, ether->bcast, sizeof(pkt->d)) != 0 && ether->prom == 0){
		if(!activemulti(ether, pkt->d, sizeof(pkt->d))){
			if(freebp){
				freeb(bp);
				bp = 0;
			}
			return bp;
		}
	}

	/*
	 * Multiplex the packet to all the connections which want it.
	 * If the packet is not to be used subsequently (freebp != 0),
	 * attempt to simply pass it into one of the connections, thereby
	 * saving a copy of the data (usual case hopefully).
	 */
	for(fp = ether->f; fp < ep; fp++){
		if((f = *fp) && (f->type == type || f->type < 0)){
			if(f->type > -2){
				if(freebp && fx == 0)
					fx = f;
				else if(xbp = iallocb(len)){
					memmove(xbp->wp, pkt, len);
					xbp->wp += len;
					qpass(f->in, xbp);
				}
				else
					ether->soverflows++;
			}
			else
				etherrtrace(f, pkt, len);
		}
	}

	if(fx){
		qpass(fx->in, bp);
		return 0;
	}
	if(freebp){
		freeb(bp);
		return 0;
	}

	return bp;
}

static int
etheroq(Ether* ether, Block* bp)
{
	int len, loopback,s;
	Etherpkt *pkt;

	ether->outpackets++;

	/*
	 * Check if the packet has to be placed back onto the input queue,
	 * i.e. if it's a loopback or broadcast packet or the interface is
	 * in promiscuous mode.
	 * If it's a loopback packet indicate to etheriq that the data isn't
	 * needed and return, etheriq will pass-on or free the block.
	 */
	pkt = (Etherpkt*)bp->rp;
	len = BLEN(bp);
	loopback = !memcmp(pkt->d, ether->ea, sizeof(pkt->d));
	if(loopback || !memcmp(pkt->d, ether->bcast, sizeof(pkt->d)) || ether->prom){
		s = splhi(); 
		etheriq(ether, bp, loopback);
		splx(s); 
	}

	if(!loopback){
		qbwrite(ether->oq, bp);
		ether->transmit(ether);
	}

	return len;
}

static long
etherwrite(Chan* chan, void* buf, long n, ulong)
{
	Ether *ether;
	Block *bp;

	if(n > ETHERMAXTU)
		error(Ebadarg);

	ether = etherxx[chan->dev];
	if(NETTYPE(chan->qid.path) != Ndataqid)
		return netifwrite(ether, chan, buf, n);

	bp = allocb(n);
	
	if(waserror()){
		freeb(bp);
		nexterror();
	}
	memmove(bp->rp, buf, n);
	memmove(bp->rp+Eaddrlen, ether->ea, Eaddrlen);
	poperror();
	bp->wp += n;

	return etheroq(ether, bp);
}

static long
etherbwrite(Chan* chan, Block* bp, ulong)
{
	Ether *ether;
	long n;

	n = BLEN(bp);
	if(n > ETHERMAXTU){
		freeb(bp);
		error(Ebadarg);
	}

	ether = etherxx[chan->dev];
	if(NETTYPE(chan->qid.path) != Ndataqid){
		n = netifwrite(ether, chan, bp->rp, n);
		freeb(bp);
		return n;
	}

	return etheroq(ether, bp);
}

static struct {
	char*	type;
	int	(*reset)(Ether*);
} cards[MaxEther+1];

void
addethercard(char* t, int (*r)(Ether*))
{
	static int ncard;

	if(ncard == MaxEther)
		panic("too many ether cards");
	cards[ncard].type = t;
	cards[ncard].reset = r;
	ncard++;
}

int
parseether(uchar *to, char *from)
{
	char nip[4];
	char *p;
	int i;

	p = from;
	for(i = 0; i < 6; i++){
		if(*p == 0)
			return -1;
		nip[0] = *p++;
		if(*p == 0)
			return -1;
		nip[1] = *p++;
		nip[2] = 0;
		to[i] = strtoul(nip, 0, 16);
		if(*p == ':')
			p++;
	}
	return 0;
}

static void
etherreset(void)
{
	Ether *ether;
	int i, n, ctlrno;
	char name[NAMELEN], buf[128];

	ethermediumlink();
	for(ether = 0, ctlrno = 0; ctlrno < MaxEther; ctlrno++){
		if(ether == 0)
			ether = malloc(sizeof(Ether));
		ether->ctlrno = ctlrno;
		ether->tbdf = BUSUNKNOWN;
		ether->mbps = 10;

		if(archether(ctlrno, ether) <= 0)
			continue;


		for(n = 0; cards[n].type; n++){
/*			print("Card #%d: type: %s looking for: %s\n",n, cards[n].type, ether->type); */
			if(cistrcmp(cards[n].type, ether->type))
				continue;
			for(i = 0; i < ether->nopt; i++){
				if(strncmp(ether->opt[i], "ea=", 3))
					continue;
				if(parseether(ether->ea, &ether->opt[i][3]) == -1)
					memset(ether->ea, 0, Eaddrlen);
			}	
			if(cards[n].reset(ether))
				break;
			intrenable(ether->irq, ether->interrupt, ether, ether->tbdf);

			i = sprint(buf, "#l%d: %s: %dMbps port 0x%luX irq %lud",
				ctlrno, ether->type, ether->mbps, ether->port, ether->irq);
			if(ether->mem)
				i += sprint(buf+i, " addr 0x%luX", ether->mem & ~KZERO);
			if(ether->size)
				i += sprint(buf+i, " size 0x%luX", ether->size);
			i += sprint(buf+i, ": %2.2uX%2.2uX%2.2uX%2.2uX%2.2uX%2.2uX",
				ether->ea[0], ether->ea[1], ether->ea[2],
				ether->ea[3], ether->ea[4], ether->ea[5]);
			sprint(buf+i, "\n");
			print(buf);

			snprint(name, sizeof(name), "ether%d", ctlrno);
			if(ether->mbps == 100){
				netifinit(ether, name, Ntypes, 256*1024);
				if(ether->oq == 0)
					ether->oq = qopen(256*1024, 1, 0, 0);
			}
			else{
				netifinit(ether, name, Ntypes, 32*1024);
				if(ether->oq == 0)
					ether->oq = qopen(64*1024, 1, 0, 0);
			}
			ether->alen = Eaddrlen;
			memmove(ether->addr, ether->ea, Eaddrlen);
			memset(ether->bcast, 0xFF, Eaddrlen);

			etherxx[ctlrno] = ether;
			ether = 0;
			break;
		}
	}
	if(ether)
		free(ether);
}

Dev etherdevtab = {
	'l',
	"ether",

	etherreset,
	devinit,
	etherattach,
	devdetach,
	devclone,
	etherwalk,
	etherstat,
	etheropen,
	ethercreate,
	etherclose,
	etherread,
	etherbread,
	etherwrite,
	etherbwrite,
	etherremove,
	etherwstat,
};
