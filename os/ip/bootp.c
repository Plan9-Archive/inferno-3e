#include "u.h"
#include "../port/lib.h"
#include "mem.h"
#include "dat.h"
#include "fns.h"
#include "../port/error.h"
#include "kernel.h"
#include "ip.h"

static	ulong	fsip;
static	ulong	auip;
static	ulong	gwip;
static	ulong	ipmask;
static	ulong	ipaddr;

uchar	sys[NAMELEN];

enum
{
	Bootrequest = 1,
	Bootreply   = 2,
};

typedef struct Bootp
{
	uchar	op;		/* opcode */
	uchar	htype;		/* hardware type */
	uchar	hlen;		/* hardware address len */
	uchar	hops;		/* hops */
	uchar	xid[4];		/* a random number */
	uchar	secs[2];	/* elapsed snce client started booting */
	uchar	pad[2];
	uchar	ciaddr[4];	/* client IP address (client tells server) */
	uchar	yiaddr[4];	/* client IP address (server tells client) */
	uchar	siaddr[4];	/* server IP address */
	uchar	giaddr[4];	/* gateway IP address */
	uchar	chaddr[16];	/* client hardware address */
	uchar	sname[64];	/* server host name (optional) */
	uchar	file[128];	/* boot file name */
	uchar	vend[128];	/* vendor-specific goo */
} Bootp;

/*
 * bootp returns:
 *
 * "fsip d.d.d.d
 * auip d.d.d.d
 * gwip d.d.d.d
 * ipmask d.d.d.d
 * ipaddr d.d.d.d"
 *
 * where d.d.d.d is the IP address in dotted decimal notation, and each
 * address is followed by a newline.
 */

static	Bootp	req;
static	Proc*	rcvprocp;
static	int	recv;
static	int	done;
static	Rendez	bootpr;
static	char	rcvbuf[512];

void
rcvbootp(void *a)
{
	int n, fd;
	Bootp *rp;
	char *field[4];
	uchar ip[IPaddrlen];

	if(waserror())
		pexit("", 0);
	rcvprocp = up;	/* store for postnote below */
	fd = (int)a;
	while(done == 0) {
		n = kread(fd, rcvbuf, sizeof(rcvbuf));
		if(n <= 0)
			break;
		rp = (Bootp*)rcvbuf;
		if(memcmp(req.chaddr, rp->chaddr, 6) == 0
		&& rp->htype == 1 && rp->hlen == 6
		&& getfields((char*)rp->vend+4, field, 4, 1, " ") == 4
		&& strncmp((char*)rp->vend, "p9  ", 4) == 0){
			if(ipaddr == 0)
				ipaddr = nhgetl(rp->yiaddr);
			if(ipmask == 0)
				ipmask = parseip(ip, field[0]);
			if(fsip == 0)
				fsip = parseip(ip, field[1]);
			if(auip == 0)
				auip = parseip(ip, field[2]);
			if(gwip == 0)
				gwip = parseip(ip, field[3]);
			break;
		}
	}
	poperror();
	rcvprocp = nil;

	recv = 1;
	wakeup(&bootpr);
	pexit("", 0);
}

char*
bootp(Ipifc *ifc)
{
	int fd, tries, n;
	char ia[5+3*16], im[16], *av[3];
	uchar nipaddr[4], ngwip[4], nipmask[4];

	av[1] = "0.0.0.0";
	av[2] = "0.0.0.0";
	ipifcadd(ifc, av, 3);

	fd = kdial("udp!255.255.255.255!67", "68", nil, nil);
	if(fd < 0)
		return "bootp dial failed";

	/* create request */
	memset(&req, 0, sizeof(req));
	req.op = Bootrequest;
	req.htype = 1;			/* ethernet (all we know) */
	req.hlen = 6;			/* ethernet (all we know) */

	/* Hardware MAC address */
	memmove(req.chaddr, ifc->mac, 6);
	/* Fill in the local IP address if we know it */
	ipv4local(ifc, req.ciaddr);
	memset(req.file, 0, sizeof(req.file));
	strcpy((char*)req.vend, "p9  ");

	done = 0;
	recv = 0;

	kproc("rcvbootp", rcvbootp, (void*)fd, KPDUPFDG);

	/*
	 * broadcast bootp's till we get a reply,
	 * or fixed number of tries
	 */
	tries = 0;
	while(recv == 0) {
		if(kwrite(fd, &req, sizeof(req)) < 0)
			print("bootp: write: %r");

		tsleep(&bootpr, return0, 0, 1000);
		if(++tries > 10) {
			print("bootp: timed out\n");
			break;
		}
	}
	kclose(fd);
	done = 1;
	if(rcvprocp != nil){
		postnote(rcvprocp, 1, "timeout", 0);
		rcvprocp = nil;
	}

	av[1] = "0.0.0.0";
	av[2] = "0.0.0.0";
	ipifcrem(ifc, av, 3, 1);

	hnputl(nipaddr, ipaddr);
	sprint(ia, "%V", nipaddr);
	hnputl(nipmask, ipmask);
	sprint(im, "%V", nipmask);
	av[1] = ia;
	av[2] = im;
	ipifcadd(ifc, av, 3);

	if(gwip != 0) {
		hnputl(ngwip, gwip);
		n = sprint(ia, "add 0.0.0.0 0.0.0.0 %V", ngwip);
		routewrite(ifc->conv->p->f, nil, ia, n);
	}
	return nil;
}

int
bootpread(char *bp, ulong offset, int len)
{
	int n;
	char *buf;
	uchar a[4];

	buf = smalloc(READSTR);
	if(waserror()){
		free(buf);
		nexterror();
	}
	hnputl(a, fsip);
	n = snprint(buf, READSTR, "fsip %15V\n", a);
	hnputl(a, auip);
	n += snprint(buf + n, READSTR-n, "auip %15V\n", a);
	hnputl(a, gwip);
	n += snprint(buf + n, READSTR-n, "gwip %15V\n", a);
	hnputl(a, ipmask);
	n += snprint(buf + n, READSTR-n, "ipmask %15V\n", a);
	hnputl(a, ipaddr);
	snprint(buf + n, READSTR-n, "ipaddr %15V\n", a);

	len = readstr(offset, bp, len, buf);
	poperror();
	free(buf);
	return len;
}
