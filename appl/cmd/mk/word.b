#
#	initially generated by c2l
#


newword(s: array of byte): ref Word
{
	w: ref Word;

	w = ref Word;
	w.s = libc0->strdup(s);
	w.next = nil;
	return w;
}

stow(s: array of byte): ref Word
{
	head, w, new: ref Word;

	w = head = nil;
	while(int s[0]){
		(new, s) = nextword(s);
		if(new == nil)
			break;
		if(w != nil)
			w.next = new;
		else
			head = w = new;
		while(w.next != nil)
			w = w.next;
	}
	if(head == nil)
		head = newword(libc0->s2ab(""));
	return head;
}

wtos(w: ref Word, sep: int): array of byte
{
	buf: ref Bufblock;
	cp: array of byte;

	buf = newbuf();
	for(; w != nil; w = w.next){
		for(cp = w.s; int cp[0]; cp = cp[1: ])
			insert(buf, int cp[0]);
		if(w.next != nil)
			insert(buf, sep);
	}
	insert(buf, 0);
	cp = libc0->strdup(buf.start);
	freebuf(buf);
	return cp;
}

wtostr(w: ref Word, sep: int): string
{
	return libc0->ab2s(wtos(w, sep));
}

wdup(w: ref Word): ref Word
{
	v, new, base: ref Word;

	v = base = nil;
	while(w != nil){
		new = newword(w.s);
		if(v != nil)
			v.next = new;
		else
			base = new;
		v = new;
		w = w.next;
	}
	return base;
}

delword(w: ref Word)
{
	v: ref Word;

	while((v = w) != nil){
		w = w.next;
		if(v.s != nil)
			v.s = nil;
		v = nil;
	}
}

# 
#  *	break out a word from a string handling quotes, executions,
#  *	and variable expansions.
#  
nextword(s: array of byte): (ref Word, array of byte)
{
	b: ref Bufblock;
	head, tail, w: ref Word;
	r, n: int;
	cp: array of byte;

	cp = s;
	b = newbuf();
	head = tail = nil;
	while(cp[0] == byte ' ' || cp[0] == byte '\t')	#  leading white space 
		cp = cp[1: ];
	loop := 1;
	while(loop && int cp[0]){
		(r, n, nil) = sys->byte2char(cp, 0);
		cp = cp[n: ];
		case(r){
		' ' or '\t' or '\n' =>
			loop = 0;
		'\\' or '\'' or '"' =>
			cp = expandquote(cp, r, b);
			if(cp == nil){
				sys->fprint(sys->fildes(2), "missing closing quote: %s\n", libc0->ab2s(s));
				Exit();
			}
		'$' =>
			(w, cp) = varsub(cp);
			if(w == nil)
				break;
			if(b.current != 0){
				bufcpy(b, w.s, libc0->strlen(w.s));
				insert(b, 0);
				w.s = nil;
				w.s = libc0->strdup(b.start);
				b.current = 0;
			}
			if(head != nil){
				bufcpy(b, tail.s, libc0->strlen(tail.s));
				bufcpy(b, w.s, libc0->strlen(w.s));
				insert(b, 0);
				tail.s = nil;
				tail.s = libc0->strdup(b.start);
				tail.next = w.next;
				w.s = nil;
				w = nil;
				b.current = 0;
			}
			else
				tail = head = w;
			while(tail.next != nil)
				tail = tail.next;
		* =>
			rinsert(b, r);
		}
	}
	s = cp;
	if(b.current != 0){
		if(head != nil){
			oc := b.current;
			cp = b.start[b.current: ];
			bufcpy(b, tail.s, libc0->strlen(tail.s));
			bufcpy(b, b.start, oc);
			insert(b, 0);
			tail.s = nil;
			tail.s = libc0->strdup(cp);
		}
		else{
			insert(b, 0);
			head = newword(b.start);
		}
	}
	freebuf(b);
	return (head, s);
}

dumpw(s: array of byte, w: ref Word)
{
	bout.puts(sys->sprint("%s", libc0->ab2s(s)));
	for(; w != nil; w = w.next)
		bout.puts(sys->sprint(" '%s'", libc0->ab2s(w.s)));
	bout.putb(byte '\n');
}
