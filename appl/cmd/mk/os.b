#
#	initially generated by c2l
#

shell := "/dis/sh.dis";
shellname := "sh";

pcopy(a: array of ref Sys->FD): array of ref Sys->FD
{
	b := array[2] of ref Sys->FD;
	b[0: ] = a[0: 2];
	return b;
}

readenv()
{
	p: array of byte;
	envf, f: ref Sys->FD;
	e := array[20] of Sys->Dir;
	nam := array[NAMELEN+5] of byte;
	i, n, lenx: int;
	w: ref Word;

	sys->pctl(Sys->FORKENV, nil);	#   use copy of the current environment variables 
	envf = sys->open("/env", Sys->OREAD);
	if(envf == nil)
		return;
	while((n = sys->dirread(envf, e)) > 0){
		n /= 1;
		for(i = 0; i < n; i++){
			lenx = e[i].length;
			#  don't import funny names, NULL values,
			# 				 * or internal mk variables
			# 				 
			if(lenx <= 0 || shname(libc0->s2ab(e[i].name))[0] != byte '\0')
				continue;
			if(symlooki(libc0->s2ab(e[i].name), S_INTERNAL, 0) != nil)
				continue;
			stob(nam, sys->sprint("/env/%s", e[i].name));
			f = sys->open(libc0->ab2s(nam), Sys->OREAD);
			if(f == nil)
				continue;
			p = array[lenx+1] of byte;
			if(sys->read(f, p, lenx) != lenx){
				perror(nam);
				f = nil;
				continue;
			}
			f = nil;
			if(p[lenx-1] == byte 0)
				lenx--;
			else
				p[lenx] = byte 0;
			w = encodenulls(p, lenx);
			p = nil;
			p = libc0->strdup(libc0->s2ab(e[i].name));
			setvar(p, w);
			symlooks(p, S_EXPORTED, libc0->s2ab("")).svalue = libc0->s2ab("");
		}
	}
	envf = nil;
}

#  break string of values into words at 01's or nulls
encodenulls(s: array of byte, n: int): ref Word
{
	w, head: ref Word;
	cp: array of byte;

	head = w = nil;
	while(n-- > 0){
		for(cp = s; int cp[0] && cp[0] != byte '\u0001'; cp = cp[1: ])
			n--;
		cp[0] = byte 0;
		if(w != nil){
			w.next = newword(s);
			w = w.next;
		}
		else
			head = w = newword(s);
		s = cp[1: ];
	}
	if(head == nil)
		head = newword(libc0->s2ab(""));
	return head;
}

#  as well as 01's, change blanks to nulls, so that rc will
#  * treat the words as separate arguments
#  
exportenv(e: array of Envy)
{
	f: ref Sys->FD;
	n, hasvalue: int;
	w: ref Word;
	sy: ref Symtab;
	nam := array[NAMELEN+5] of byte;

	for(i := 0; e[i].name != nil; i++){
		sy = symlooki(e[i].name, S_VAR, 0);
		if(e[i].values == nil || e[i].values.s == nil || e[i].values.s[0] == byte 0)
			hasvalue = 0;
		else
			hasvalue = 1;
		if(sy == nil && !hasvalue)	#  non-existant null symbol 
			continue;
		stob(nam, sys->sprint("/env/%s", libc0->ab2s(e[i].name)));
		if(sy != nil && !hasvalue){	#  Remove from environment 
			#  we could remove it from the symbol table
			# 				 * too, but we're in the child copy, and it
			# 				 * would still remain in the parent's table.
			# 				 
			sys->remove(libc0->ab2s(nam));
			delword(e[i].values);
			e[i].values = nil;	#  memory leak 
			continue;
		}
		f = sys->create(libc0->ab2s(nam), Sys->OWRITE, 8r666);
		if(f == nil){
			sys->fprint(sys->fildes(2), "can't create %s, f=%d\n", libc0->ab2s(nam), f.fd);
			perror(nam);
			continue;
		}
		for(w = e[i].values; w != nil; w = w.next){
			n = libc0->strlen(w.s);
			if(n){
				if(sys->write(f, w.s, n) != n)
					perror(nam);
				if(w.next != nil && sys->write(f, libc0->s2ab(" "), 1) != 1)
					perror(nam);
			}
		}
		f = nil;
	}
}

dirtime(dir: array of byte, path: array of byte)
{
	i: int;
	fd: ref Sys->FD;
	n: int;
	t: int;
	db := array[32] of Sys->Dir;
	buf := array[4096] of byte;

	fd = sys->open(libc0->ab2s(dir), Sys->OREAD);
	if(fd != nil){
		while((n = sys->dirread(fd, db)) > 0){
			n /= 1;
			for(i = 0; i < n; i++){
				t = db[i].mtime;
				if(t == 0)	#  zero mode file 
					continue;
				stob(buf, sys->sprint("%s%s", libc0->ab2s(path), db[i].name));
				if(symlooki(buf, S_TIME, 0) != nil)
					continue;
				symlooki(libc0->strdup(buf), S_TIME, t).ivalue = t;
			}
		}
		fd = nil;
	}
}

waitfor(msg: array of byte): int
{
	wm: array of byte;
	pid: int;

	(pid, wm) = wait();
	if(pid > 0)
		libc0->strncpy(msg, wm, ERRLEN);
	return pid;
}

expunge(pid: int, msg: array of byte)
{
	postnote(PNPROC, pid, msg);
}

sub(cmd: array of byte, env: array of Envy): array of byte
{
	buf := newbuf();
	shprint(cmd, env, buf);
	return buf.start;
}

fork1(c1: chan of int, args: array of byte, cmd: array of byte, buf: ref Bufblock, e: array of Envy, in: array of ref Sys->FD, out: array of ref Sys->FD)
{
	pid: int;

	c1<- = sys->pctl(Sys->FORKFD|Sys->FORKENV, nil);

	{
		if(buf != nil)
			out[0] = nil;
		if(sys->pipe(in) < 0){
			perrors("pipe");
			Exit();
		}
		c2 := chan of int;
		spawn fork2(c2, cmd, pcopy(in), pcopy(out));
		pid = <- c2;
		addwait();
		{
			sys->dup(in[0].fd, 0);
			if(buf != nil){
				sys->dup(out[1].fd, 1);
				out[1] = nil;
			}
			in[0] = nil;
			in[1] = nil;
			if(e != nil)
				exportenv(e);
			argss := libc0->ab2s(args);
			if(shflags != nil)
				execl(shell, shellname, shflags, argss, nil, nil);
			else
				execl(shell, shellname, argss, nil, nil, nil);
			exit;
			# perror(shell);
			# exits("exec");
		}
	}
}

fork2(c2: chan of int, cmd: array of byte, in: array of ref Sys->FD, out: array of ref Sys->FD)
{
	n, p: int;

	c2<- = sys->pctl(Sys->FORKFD, nil);

	{
		out[1] = nil;
		in[0] = nil;
		p = libc0->strlen(cmd);
		c := 0;
		while(c < p){	# cmd < p
			if(debug&D_EXEC)
				sys->fprint(sys->fildes(1), "writing '%s' to shell\n", libc0->ab2s(cmd[0: p-c]));
			n = sys->write(in[1], cmd, p-c);	# p-cmd
			if(n < 0)
				break;
			cmd = cmd[n: ];
			c += n;
		}
		in[1] = nil;
		exit;
		# exits(nil);
	}
}

execsh(args: array of byte, cmd: array of byte, buf: ref Bufblock, e: array of Envy): int
{
	tot, n, pid: int;
	in := array[2] of ref Sys->FD;
	out := array[2] of ref Sys->FD;

	cmd = sub(cmd, e);

	if(buf != nil && sys->pipe(out) < 0){
		perrors("pipe");
		Exit();
	}
	c1 := chan of int;
	spawn fork1(c1, args, cmd, buf, e, in, pcopy(out));
	pid = <-c1;
	addwait();
	if(buf != nil){
		out[1] = nil;
		tot = 0;
		for(;;){
			if(buf.current >= buf.end)
				growbuf(buf);
			n = sys->read(out[0], buf.start[buf.current: ], buf.end-buf.current);
			if(n <= 0)
				break;
			buf.current += n;
			tot += n;
		}
		if(tot && buf.start[buf.current-1] == byte '\n')
			buf.current--;
		out[0] = nil;
	}
	return pid;
}

fork3(c3: chan of int, cmd: array of byte, e: array of Envy, fd: array of ref Sys->FD, pfd: array of ref Sys->FD)
{
	c3<- = sys->pctl(Sys->FORKFD|Sys->FORKENV, nil);

	{
		if(fd != nil){
			pfd[0] = nil;
			sys->dup(pfd[1].fd, 1);
			pfd[1] = nil;
		}
		if(e != nil)
			exportenv(e);
		cmds := libc0->ab2s(cmd);
		if(shflags != nil)
			execl(shell, shellname, shflags, "-c", cmds, nil);
		else
			execl(shell, shellname, "-c", cmds, nil, nil);
		exit;
		# perror(shell);
		# exits("exec");
	}
}

pipecmd(cmd: array of byte, e: array of Envy, fd: array of ref Sys->FD): int
{
	pid: int;
	pfd := array[2] of ref Sys->FD;

	cmd = sub(cmd, e);

	if(debug&D_EXEC)
		sys->fprint(sys->fildes(1), "pipecmd='%s'", libc0->ab2s(cmd));	# 
	if(fd != nil && sys->pipe(pfd) < 0){
		perrors("pipe");
		Exit();
	}
	c3 := chan of int;
	spawn fork3(c3, cmd, e, fd, pcopy(pfd));
	pid = <- c3;
	addwait();
	if(fd != nil){
		pfd[1] = nil;
		fd[0] = pfd[0];
	}
	return pid;
}

Exit()
{
	while(wait().t0 >= 0)
		;
	bout.flush();
	exit;
}

nnote: int;

notifyf(a: array of byte, msg: array of byte): int
{
	if(a != nil)
		;
	if(++nnote > 100){	#  until andrew fixes his program 
		sys->fprint(sys->fildes(2), "mk: too many notes\n");
		# notify(nil);
		abort();
	}
	if(libc0->strcmp(msg, libc0->s2ab("interrupt")) != 0 && libc0->strcmp(msg, libc0->s2ab("hangup")) != 0)
		return 0;
	killchildren(msg);
	return -1;
}

catchnotes()
{
	# atnotify(notifyf, 1);
}

temp := array[] of { byte '/', byte 't', byte 'm', byte 'p', byte '/', byte 'm', byte 'k', byte 'a', byte 'r', byte 'g', byte 'X', byte 'X', byte 'X', byte 'X', byte 'X', byte 'X', byte '\0' };

maketmp(): array of byte
{
	t := libc0->strdup(temp);
	mktemp(t);
	return t;
}

chgtime(name: array of byte): int
{
	(ok, sbuf) := sys->stat(libc0->ab2s(name));
	if(ok >= 0){
		sbuf.mtime = daytime->now();
		return sys->wstat(libc0->ab2s(name), sbuf);
	}
	fd := sys->create(libc0->ab2s(name), Sys->OWRITE, 8r666);
	if(fd == nil)
		return -1;
	fd = nil;
	return 0;
}

rcopy(tox: array of array of byte, match: array of Resub, n: int)
{
	c: int;
	p: array of byte;

	i := 0;
	tox[0] = match[0].sp;	#  stem0 matches complete target 
	for(i++; --n > 0; i++){
		if(match[i].sp != nil && match[i].ep != nil){
			p = match[i].ep;
			c = int p[0];
			p[0] = byte 0;
			tox[i] = libc0->strdup(match[i].sp);
			p[0] = byte c;
		}
		else
			tox[i] = nil;
	}
}

mkdirstat(name: array of byte): (int, Sys->Dir)
{
	return sys->stat(libc0->ab2s(name));
}

membername(s: array of byte, fd: ref Sys->FD, sz: int): array of byte
{
	if(fd == nil)
		;
	if(sz)
		;
	return s;
}

