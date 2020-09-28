#include	"dat.h"
#include	"fns.h"
#include	"error.h"
#include	<interp.h>
#include	<isa.h>
#include	"runt.h"

#define NETTYPE(x)	((ulong)(x)&0x1f)
#define NETID(x)	(((ulong)(x)&~CHDIR)>>5)
#define NETQID(i,t)	(((i)<<5)|(t))

typedef struct Pipe	Pipe;
struct Pipe
{
	QLock	l;
	Pipe*	next;
	int	ref;
	ulong	path;
	Queue*	q[2];
	int	qref[2];
	Dirtab *pipedir;
};

struct
{
	Lock	l;
	ulong	path;
	int	pipeqsize;	
} pipealloc;

enum
{
	Qdir,
	Qdata0,
	Qdata1
};

Dirtab pipedir[] =
{
	"data",		{Qdata0},	0,			0666,
	"data1",	{Qdata1},	0,			0666,
};
#define NPIPEDIR 2

static void
pipeinit(void)
{
	pipealloc.pipeqsize = 32*1024;
}

/*
 *  create a pipe, no streams are created until an open
 */
static Chan*
pipeattach(char *spec)
{
	Pipe *p;
	Chan *c;

	c = devattach('|', spec);
	p = malloc(sizeof(Pipe));
	if(p == 0)
		error(Enomem);
	p->pipedir = malloc(sizeof(pipedir));
	if (p->pipedir == 0) {
		free(p);
		error(Enomem);
	}
	memmove(p->pipedir, pipedir, sizeof(pipedir));
	p->ref = 1;

	p->q[0] = qopen(pipealloc.pipeqsize, 0, 0, 0);
	if(p->q[0] == 0){
		free(p->pipedir);
		free(p);
		error(Enomem);
	}
	p->q[1] = qopen(pipealloc.pipeqsize, 0, 0, 0);
	if(p->q[1] == 0){
		free(p->q[0]);
		free(p->pipedir);
		free(p);
		error(Enomem);
	}

	lock(&pipealloc.l);
	p->path = ++pipealloc.path;
	unlock(&pipealloc.l);

	c->qid.path = CHDIR|NETQID(2*p->path, Qdir);
	c->qid.vers = 0;
	c->u.aux = p;
	c->dev = 0;
	return c;
}

static Chan*
pipeclone(Chan *c, Chan *nc)
{
	Pipe *p;

	p = c->u.aux;
	nc = devclone(c, nc);
	qlock(&p->l);
	p->ref++;
	if(c->flag & COPEN){
		switch(NETTYPE(c->qid.path)){
		case Qdata0:
			p->qref[0]++;
			break;
		case Qdata1:
			p->qref[1]++;
			break;
		}
	}
	qunlock(&p->l);
	return nc;
}

static int
pipegen(Chan *c, Dirtab *tab, int ntab, int i, Dir *dp)
{
	int id;
	Qid qid;

	if(i == DEVDOTDOT){
		devdir(c, c->qid, "#|", 0, eve, 0555, dp);
		return 1;
	}

	id = NETID(c->qid.path);
	if(i > 1)
		id++;
	if(tab==0 || i>=ntab)
		return -1;
	tab += i;
	qid.path = NETQID(id, tab->qid.path);
	qid.vers = 0;
	devdir(c, qid, tab->name, tab->length, eve, tab->perm, dp);
	return 1;
}


static int
pipewalk(Chan *c, char *name)
{
	Pipe *p;
	p = c->u.aux;
	return devwalk(c, name, p->pipedir, NPIPEDIR, pipegen);
}

static void
pipestat(Chan *c, char *db)
{
	Pipe *p;
	Dir dir;
	Dirtab *tab;

	p = c->u.aux;
	tab = p->pipedir;

	switch(NETTYPE(c->qid.path)){
	case Qdir:
		devdir(c, c->qid, "#|", 0, eve, CHDIR|0555, &dir);
		break;
	case Qdata0:
		devdir(c, c->qid, tab[0].name, qlen(p->q[0]), eve, tab[0].perm, &dir);
		break;
	case Qdata1:
		devdir(c, c->qid, tab[1].name, qlen(p->q[1]), eve, tab[1].perm, &dir);
		break;
	default:
		panic("pipestat");
	}
	convD2M(&dir, db);
}

/*
 *  if the stream doesn't exist, create it
 */
static Chan*
pipeopen(Chan *c, int omode)
{
	Pipe *p;

	if(c->qid.path & CHDIR){
		if(omode != OREAD)
			error(Ebadarg);
		c->mode = omode;
		c->flag |= COPEN;
		c->offset = 0;
		return c;
	}

	p = c->u.aux;
	qlock(&p->l);
	switch(NETTYPE(c->qid.path)){
	case Qdata0:
		p->qref[0]++;
		break;
	case Qdata1:
		p->qref[1]++;
		break;
	}
	qunlock(&p->l);

	c->mode = openmode(omode);
	c->flag |= COPEN;
	c->offset = 0;
	return c;
}

static void
pipeclose(Chan *c)
{
	Pipe *p;

	p = c->u.aux;
	qlock(&p->l);

	if(c->flag & COPEN){
		/*
		 *  closing either side hangs up the stream
		 */
		switch(NETTYPE(c->qid.path)){
		case Qdata0:
			p->qref[0]--;
			if(p->qref[0] == 0){
				qhangup(p->q[1], 0);
				qclose(p->q[0]);
			}
			break;
		case Qdata1:
			p->qref[1]--;
			if(p->qref[1] == 0){
				qhangup(p->q[0], 0);
				qclose(p->q[1]);
			}
			break;
		}
	}

	
	/*
	 *  if both sides are closed, they are reusable
	 */
	if(p->qref[0] == 0 && p->qref[1] == 0){
		qreopen(p->q[0]);
		qreopen(p->q[1]);
	}

	/*
	 *  free the structure on last close
	 */
	p->ref--;
	if(p->ref == 0){
		qunlock(&p->l);
		free(p->q[0]);
		free(p->q[1]);
		free(p->pipedir);
		free(p);
	} else
		qunlock(&p->l);
}

static long
piperead(Chan *c, void *va, long n, ulong junk)
{
	Pipe *p;

	p = c->u.aux;

	USED(junk);
	switch(NETTYPE(c->qid.path)){
	case Qdir:
		return devdirread(c, va, n, p->pipedir, NPIPEDIR, pipegen);
	case Qdata0:
		return qread(p->q[0], va, n);
	case Qdata1:
		return qread(p->q[1], va, n);
	default:
		panic("piperead");
	}
	return -1;	/* not reached */
}

static Block*
pipebread(Chan *c, long n, ulong offset)
{
	Pipe *p;

	p = c->u.aux;

	switch(NETTYPE(c->qid.path)){
	case Qdata0:
		return qbread(p->q[0], n);
	case Qdata1:
		return qbread(p->q[1], n);
	}

	return devbread(c, n, offset);
}

/*
 *  a write to a closed pipe causes an exception to be sent to
 *  the prog.
 */
static long
pipewrite(Chan *c, void *va, long n, ulong junk)
{
	Pipe *p;
	Prog *r;

	USED(junk);
	if(waserror()) {
		/* avoid exceptions when pipe is a mounted queue */
		if((c->flag & CMSG) == 0) {
			r = up->iprog;
			if(r->kill == nil)
				r->kill = "write on closed pipe";
		}
		nexterror();
	}

	p = c->u.aux;

	switch(NETTYPE(c->qid.path)){
	case Qdata0:
		n = qwrite(p->q[1], va, n);
		break;

	case Qdata1:
		n = qwrite(p->q[0], va, n);
		break;

	default:
		panic("pipewrite");
	}

	poperror();
	return n;
}

static long
pipebwrite(Chan *c, Block *bp, ulong junk)
{
	long n;
	Pipe *p;
	Prog *r;

	USED(junk);
	if(waserror()) {
		/* avoid exceptions when pipe is a mounted queue */
		if((c->flag & CMSG) == 0) {
			r = up->iprog;
			if(r->kill == nil)
				r->kill = "write on closed pipe";
		}
		nexterror();
	}

	p = c->u.aux;
	switch(NETTYPE(c->qid.path)){
	case Qdata0:
		n = qbwrite(p->q[1], bp);
		break;

	case Qdata1:
		n = qbwrite(p->q[0], bp);
		break;

	default:
		n = 0;
		panic("pipebwrite");
	}

	poperror();
	return n;
}

static void
pipewstat(Chan *c, char *db)
{
	Dir d;
	Pipe *p;
	int d1;

	if (c->qid.path&CHDIR)
		error(Eperm);

	p = c->u.aux;
	d1 = NETTYPE(c->qid.path) == Qdata1;
	/* XXX what permission checking is appropriate here? */

	convM2D(db, &d);
	if (!strcmp(p->pipedir[!d1].name, d.name))
		error("file already exists");
	strcpy(p->pipedir[d1].name, d.name);
	p->pipedir[d1].perm = d.mode & 0777;
}

Dev pipedevtab = {
	'|',
	"pipe",

	pipeinit,
	pipeattach,
	pipeclone,
	pipewalk,
	pipestat,
	pipeopen,
	devcreate,
	pipeclose,
	piperead,
	pipebread,
	pipewrite,
	pipebwrite,
	devremove,
	pipewstat,
};
