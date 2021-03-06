#include "limbo.h"

void
asmentry(Decl *e)
{
	if(e == nil)
		return;
	Bprint(bout, "\tentry\t%ld, %d\n", e->pc->pc, e->desc->id);
}

void
asmmod(Decl *m)
{
	Bprint(bout, "\tmodule\t");
	Bprint(bout, "%s\n", m->sym->name);
	for(m = m->ty->tof->ids; m != nil; m = m->next){
		switch(m->store){
		case Dglobal:
			Bprint(bout, "\tlink\t-1,-1,0x%lux,\".mp\"\n", sign(m));
			break;
		case Dfn:
			Bprint(bout, "\tlink\t%d,%ld,0x%lux,\"",
				m->desc->id, m->pc->pc, sign(m));
			if(m->dot->ty->kind == Tadt)
				Bprint(bout, "%s.", m->dot->sym->name);
			Bprint(bout, "%s\"\n", m->sym->name);
			break;
		}
	}
}

void
asmdesc(Desc *d)
{
	uchar *m, *e;

	for(; d != nil; d = d->next){
		Bprint(bout, "\tdesc\t$%d,%lud,\"", d->id, d->size);
		e = d->map + d->nmap;
		for(m = d->map; m < e; m++)
			Bprint(bout, "%.2x", *m);
		Bprint(bout, "\"\n");
	}
}

void
asmvar(long size, Decl *d)
{
	Bprint(bout, "\tvar\t@mp,%ld\n", size);

	for(; d != nil; d = d->next)
		if(d->store == Dglobal && d->init != nil)
			asminitializer(d->offset, d->init);
}

void
asminitializer(long offset, Node *n)
{
	Node *elem, *wild;
	Case *c;
	Label *lab;
	Decl *id;
	ulong dv[2];
	long e, last, esz, dotlen, idlen;
	int i;

	switch(n->ty->kind){
	case Tbyte:
		Bprint(bout, "\tbyte\t@mp+%ld,%ld\n", offset, (long)n->val & 0xff);
		break;
	case Tint:
		Bprint(bout, "\tword\t@mp+%ld,%ld\n", offset, (long)n->val);
		break;
	case Tbig:
		Bprint(bout, "\tlong\t@mp+%ld,%lld # %.16llux\n", offset, n->val, n->val);
		break;
	case Tstring:
		asmstring(offset, n->decl->sym);
		break;
	case Treal:
		dtocanon(n->rval, dv);
		Bprint(bout, "\treal\t@mp+%ld,%g # %.8lux%.8lux\n", offset, n->rval, dv[0], dv[1]);
		break;
	case Tadt:
	case Tadtpick:
	case Ttuple:
		id = n->ty->ids;
		for(n = n->left; n != nil; n = n->right){
			asminitializer(offset + id->offset, n->left);
			id = id->next;
		}
		break;
	case Tcase:
		c = n->ty->cse;
		Bprint(bout, "\tword\t@mp+%ld,%d", offset, c->nlab);
		for(i = 0; i < c->nlab; i++){
			lab = &c->labs[i];
			Bprint(bout, ",%ld,%ld,%ld", (long)lab->start->val, (long)lab->stop->val+1, lab->inst->pc);
		}
		Bprint(bout, ",%ld\n", c->iwild->pc);
		break;
	case Tcasec:
		c = n->ty->cse;
		Bprint(bout, "\tword\t@mp+%ld,%d\n", offset, c->nlab);
		offset += IBY2WD;
		for(i = 0; i < c->nlab; i++){
			lab = &c->labs[i];
			asmstring(offset, lab->start->decl->sym);
			offset += IBY2WD;
			if(lab->stop != lab->start)
				asmstring(offset, lab->stop->decl->sym);
			offset += IBY2WD;
			Bprint(bout, "\tword\t@mp+%ld,%ld\n", offset, lab->inst->pc);
			offset += IBY2WD;
		}
		Bprint(bout, "\tword\t@mp+%ld,%d\n", offset, c->iwild->pc);
		break;
	case Tgoto:
		c = n->ty->cse;
		Bprint(bout, "\tword\t@mp+%ld", offset);
		Bprint(bout, ",%ld", n->ty->size/IBY2WD-1);
		for(i = 0; i < c->nlab; i++)
			Bprint(bout, ",%ld", c->labs[i].inst->pc);
		if(c->iwild != nil)
			Bprint(bout, ",%ld", c->iwild->pc);
		Bprint(bout, "\n");
		break;
	case Tany:
		break;
	case Tarray:
		Bprint(bout, "\tarray\t@mp+%ld,$%d,%ld\n", offset, n->ty->tof->decl->desc->id, (long)n->left->val);
		if(n->right == nil)
			break;
		Bprint(bout, "\tindir\t@mp+%ld,0\n", offset);
		c = n->right->ty->cse;
		wild = nil;
		if(c->wild != nil)
			wild = c->wild->right;
		last = 0;
		esz = n->ty->tof->size;
		for(i = 0; i < c->nlab; i++){
			e = c->labs[i].start->val;
			if(wild != nil){
				for(; last < e; last++)
					asminitializer(esz * last, wild);
			}
			last = e;
			e = c->labs[i].stop->val;
			elem = c->labs[i].node->right;
			for(; last <= e; last++)
				asminitializer(esz * last, elem);
		}
		if(wild != nil)
			for(e = n->left->val; last < e; last++)
				asminitializer(esz * last, wild);
		Bprint(bout, "\tapop\n");
		break;
	case Tiface:
		Bprint(bout, "\tword\t@mp+%d,%d\n", offset, (long)n->val);
		offset += IBY2WD;
		for(id = n->decl->ty->ids; id != nil; id = id->next){
			offset = align(offset, IBY2WD);
			Bprint(bout, "\text\t@mp+%d,0x%lux,\"", offset, sign(id));
			dotlen = 0;
			idlen = id->sym->len + 1;
			if(id->dot->ty->kind == Tadt){
				dotlen = id->dot->sym->len + 1;
				Bprint(bout, "%s.", id->dot->sym->name);
			}
			Bprint(bout, "%s\"\n", id->sym->name);
			offset += idlen + dotlen + IBY2WD;
		}
		break;
	default:
		nerror(n, "can't asm global %n", n);
		break;
	}
}

void
asmstring(long offset, Sym *sym)
{
	char *s, *se;
	int c;

	Bprint(bout, "\tstring\t@mp+%ld,\"", offset);
	s = sym->name;
	se = s + sym->len;
	for(; s < se; s++){
		c = *s;
		if(c == '\n')
			Bwrite(bout, "\\n", 2);
		else if(c == '\0')
			Bwrite(bout, "\\z", 2);
		else if(c == '"')
			Bwrite(bout, "\\\"", 2);
		else if(c == '\\')
			Bwrite(bout, "\\\\", 2);
		else
			Bputc(bout, c);
	}
	Bprint(bout, "\"\n");
}

void
asminst(Inst *in)
{
	for(; in != nil; in = in->next){
		if(in->pc % 10 == 0)
			Bprint(bout, "#%d\n", in->pc);
		Bprint(bout, "%I\n", in);
	}
}
