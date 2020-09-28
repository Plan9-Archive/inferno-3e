#include	"cc.h"
#include	"y.tab.h"

enum
{
	Fnone	= 0,
	Fl,
	Fvl,
	Fignor,
	Fstar,
	Fadj,

	Fverb	= 10,
};

typedef	struct	Tprot	Tprot;
struct	Tprot
{
	Type*	type;
	Bits	flag;
	Tprot*	link;
};

typedef	struct	Tname	Tname;
struct	Tname
{
	char*	name;
	int	param;
	Tname*	link;
};

static	Type*	indchar;
static	uchar	flagbits[256];
static	char	fmtbuf[100];
static	int	lastadj;
static	int	lastverb;
static	int	nstar;
static	Tprot*	tprot;
static	Tname*	tname;

void
argflag(int c, int v)
{

	switch(v) {
	case Fignor:
	case Fstar:
	case Fl:
	case Fvl:
		flagbits[c] = v;
		break;
	case Fverb:
		flagbits[c] = lastverb;
/*print("flag-v %c %d\n", c, lastadj);*/
		lastverb++;
		break;
	case Fadj:
		flagbits[c] = lastadj;
/*print("flag-l %c %d\n", c, lastadj);*/
		lastadj++;
		break;
	}
}

Bits
getflag(char *s)
{
	Bits flag;
	int c, f;
	char *fmt;

	fmt = fmtbuf;
	flag = zbits;
	nstar = 0;
	while(c = *s++) {
		*fmt++ = c;
		f = flagbits[c];
		switch(f) {
		case Fnone:
			argflag(c, Fverb);
			f = flagbits[c];
			break;
		case Fstar:
			nstar++;
		case Fignor:
			continue;
		case Fl:
			if(bset(flag, Fl))
				flag = bor(flag, blsh(Fvl));
		}
		flag = bor(flag, blsh(f));
		if(f >= Fverb)
			break;
	}
	*fmt = 0;
	return flag;
}

void
newprot(Sym *m, Type *t, char *s)
{
	Bits flag;
	Tprot *l;

	if(t == T) {
		warn(Z, "%s: newprot: type not defined", m->name);
		return;
	}
	flag = getflag(s);
	for(l=tprot; l; l=l->link)
		if(beq(flag, l->flag) && sametype(t, l->type))
			return;
	l = alloc(sizeof(*l));
	l->type = t;
	l->flag = flag;
	l->link = tprot;
	tprot = l;
}

void
newname(char *s, int p)
{
	Tname *l;

	for(l=tname; l; l=l->link)
		if(strcmp(l->name, s) == 0) {
			if(l->param != p)
				yyerror("vargck %s already defined\n", s);
			return;
		}
	l = alloc(sizeof(*l));
	l->name = s;
	l->param = p;
	l->link = tname;
	tname = l;
}

void
arginit(void)
{
	int i;

/* debug['F'] = 1;*/
/* debug['w'] = 1;*/

	lastadj = Fadj;
	lastverb = Fverb;
	indchar = typ(TIND, types[TCHAR]);

	memset(flagbits, Fnone, sizeof(flagbits));

	for(i='0'; i<='9'; i++)
		argflag(i, Fignor);
	argflag('.', Fignor);
	argflag('#', Fignor);
	argflag('u', Fignor);
	argflag('+', Fignor);
	argflag('-', Fignor);

	argflag('*', Fstar);
	argflag('l', Fl);

	argflag('o', Fverb);
	flagbits['x'] = flagbits['o'];
	flagbits['X'] = flagbits['o'];
}

void
pragvararg(void)
{
	Sym *s;
	int n, c;
	char *t;

	if(!debug['F'])
		goto out;
	s = getsym();
	if(s && strcmp(s->name, "argpos") == 0)
		goto ckpos;
	if(s && strcmp(s->name, "type") == 0)
		goto cktype;
	yyerror("syntax in #pragma varargck");
	goto out;

ckpos:
/*#pragma	varargck	argpos	warn	2*/
	s = getsym();
	if(s == S)
		goto bad;
	n = getnsn();
	if(n < 0)
		goto bad;
	newname(s->name, n);
	goto out;

cktype:
/*#pragma	varargck	type	O	int*/
	c = getnsc();
	if(c != '"')
		goto bad;
	t = fmtbuf;
	for(;;) {
		c = getc();
		if(c == ' ' || c == '\n')
			goto bad;
		if(c == '"')
			break;
		*t++ = c;
	}
	*t = 0;
	t = strdup(fmtbuf);
	s = getsym();
	if(s == S)
		goto bad;
	c = getnsc();
	unget(c);
	if(c == '*')
		newprot(s, typ(TIND, s->type), t);
	else
		newprot(s, s->type, t);
	goto out;

bad:
	yyerror("syntax in #pragma varargck");

out:
	while(getnsc() != '\n')
		;
}

Node*
nextarg(Node *n, Node **a)
{
	if(n == Z) {
		*a = Z;
		return Z;
	}
	if(n->op == OLIST) {
		*a = n->left;
		return n->right;
	}
	*a = n;
	return Z;
}

void
checkargs(Node *nn, char *s, int pos)
{
	Node *a, *n;
	Bits flag;
	Tprot *l;

	if(!debug['F'])
		return;
	n = nn;
	for(;;) {
		s = strchr(s, '%');
		if(s == 0) {
			nextarg(n, &a);
			if(a != Z)
				warn(nn, "more arguments than format %T",
					a->type);
			return;
		}
		s++;
		flag = getflag(s);
		while(nstar > 0) {
			n = nextarg(n, &a);
			pos++;
			nstar--;
			if(a == Z) {
				warn(nn, "more format than arguments %s",
					fmtbuf);
				return;
			}
			if(a->type == T)
				continue;
			if(!sametype(types[TINT], a->type) &&
			   !sametype(types[TUINT], a->type))
				warn(nn, "format mismatch '*' in %s %T, arg %d",
					fmtbuf, a->type, pos);
		}
		for(l=tprot; l; l=l->link)
			if(sametype(types[TVOID], l->type)) {
				if(beq(flag, l->flag)) {
					s++;
					goto loop;
				}
			}

		n = nextarg(n, &a);
		pos++;
		if(a == Z) {
			warn(nn, "more format than arguments %s",
				fmtbuf);
			return;
		}
		if(a->type == 0)
			continue;
		for(l=tprot; l; l=l->link)
			if(sametype(a->type, l->type))
				if(beq(flag, l->flag))
					goto loop;
		warn(nn, "format mismatch %s %T, arg %d", fmtbuf, a->type, pos);
	loop:;
	}
}

void
dpcheck(Node *n)
{
	char *s;
	Node *a, *b;
	Tname *l;
	int i;

	if(n == Z)
		return;
	b = n->left;
	if(b == Z || b->op != ONAME)
		return;
	s = b->sym->name;
	for(l=tname; l; l=l->link)
		if(strcmp(s, l->name) == 0)
			break;
	if(l == 0)
		return;

	i = l->param;
	b = n->right;
	while(i > 0) {
		b = nextarg(b, &a);
		i--;
	}
	if(a == Z) {
		warn(n, "cant find format arg");
		return;
	}
	if(!sametype(indchar, a->type)) {
		warn(n, "format arg type %T", a->type);
		return;
	}
	if(a->op != OADDR || a->left->op != ONAME || a->left->sym != symstring) {
/*		warn(n, "format arg not constant string");*/
		return;
	}
	s = a->left->cstring;
	checkargs(b, s, l->param);
}

void
praghjdicks(void)
{
	Sym *s;

	hjdickflg = 0;
	s = getsym();
	if(s) {
		hjdickflg = atoi(s->name+1);
		if(strcmp(s->name, "on") == 0 ||
		   strcmp(s->name, "yes") == 0 ||
		   strcmp(s->name, "dick") == 0)
			hjdickflg = 1;
	}
	while(getnsc() != '\n')
		;
	if(debug['f'])
		if(hjdickflg)
			print("%4ld: hjdicks %d\n", lineno, hjdickflg);
		else
			print("%4ld: hjdicks off\n", lineno);
}

void
pragfpround(void)
{
	Sym *s;

	fproundflg = 0;
	s = getsym();
	if(s) {
		hjdickflg = atoi(s->name+1);
		if(strcmp(s->name, "on") == 0 ||
		   strcmp(s->name, "yes") == 0 ||
		   strcmp(s->name, "dick") == 0)
			fproundflg = 1;
	}
	while(getnsc() != '\n')
		;
	if(debug['f'])
		if(fproundflg)
			print("%4ld: fproundflg %d\n", lineno, fproundflg);
		else
			print("%4ld: fproundflg off\n", lineno);
}
