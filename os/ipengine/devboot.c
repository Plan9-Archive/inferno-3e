#include	"u.h"
#include	"../port/lib.h"
#include	"mem.h"
#include	"dat.h"
#include	"fns.h"
#include	"../port/error.h"

enum{
	Qdir,
	Qboot,
	Qmem,
};

Dirtab bootdir[]={
	"boot",		{Qboot},	0,	0666,
	"mem",		{Qmem},		0,	0666,
};

#define	NBOOT	(sizeof bootdir/sizeof(Dirtab))

static void
bootreset(void)
{
}

static Chan*
bootattach(char *spec)
{
	return devattach('B', spec);
}

static int	 
bootwalk(Chan *c, char *name)
{
	return devwalk(c, name, bootdir, NBOOT, devgen);
}

static void	 
bootstat(Chan *c, char *dp)
{
	devstat(c, dp, bootdir, NBOOT, devgen);
}

static Chan*
bootopen(Chan *c, int omode)
{
	return devopen(c, omode, bootdir, NBOOT, devgen);
}

static void	 
bootclose(Chan*)
{
}

static long	 
bootread(Chan *c, void *buf, long n, ulong offset)
{
	switch(c->qid.path & ~CHDIR){

	case Qdir:
		return devdirread(c, buf, n, bootdir, NBOOT, devgen);

	case Qmem:
		/* kernel memory */
		if(offset>=KZERO && offset<KZERO+conf.npage*BY2PG){
			if(offset+n > KZERO+conf.npage*BY2PG)
				n = KZERO+conf.npage*BY2PG - offset;
			memmove(buf, (char*)offset, n);
			return n;
		}
		error(Ebadarg);
	}

	error(Egreg);
	return 0;	/* not reached */
}

static long	 
bootwrite(Chan *c, void *buf, long n, ulong offset)
{
	ulong pc;
	uchar *p;

	switch(c->qid.path & ~CHDIR){
	case Qmem:
		/* kernel memory */
		if(offset>=KZERO && offset<KZERO+conf.npage*BY2PG){
			if(offset+n > KZERO+conf.npage*BY2PG)
				n = KZERO+conf.npage*BY2PG - offset;
			memmove((char*)offset, buf, n);
			segflush((void*)offset, n);
			return n;
		}
		error(Ebadarg);

	case Qboot:
		p = (uchar*)buf;
		pc = (((((p[0]<<8)|p[1])<<8)|p[2])<<8)|p[3];
		if(pc < KZERO || pc >= KZERO+conf.npage*BY2PG)
			error(Ebadarg);
		splhi();
		segflush((void*)pc, 64*1024);
		gotopc(pc);
	}
	error(Ebadarg);
	return 0;	/* not reached */
}

Dev bootdevtab = {
	'B',
	"boot",

	bootreset,
	devinit,
	bootattach,
	devdetach,
	devclone,
	bootwalk,
	bootstat,
	bootopen,
	devcreate,
	bootclose,
	bootread,
	devbread,
	bootwrite,
	devbwrite,
	devremove,
	devwstat,
};
