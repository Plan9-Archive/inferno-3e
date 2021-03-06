implement Shellbuiltin;

include "sys.m";
	sys: Sys;
include "draw.m";
include "tk.m";
	tk: Tk;
include "wmlib.m";
	wmlib: Wmlib;
include "lock.m";
	lock: Lock;
	Semaphore: import lock;
include "sh.m";
	sh: Sh;
	Listnode, Context: import sh;
	myself: Shellbuiltin;

tklock: ref Lock->Semaphore;

chans := array[23] of list of (string, chan of string);
wins := array[16] of list of (int, ref Tk->Toplevel);
winid := 0;

badmodule(ctxt: ref Context, p: string)
{
	ctxt.fail("bad module", sys->sprint("tk: cannot load %s: %r", p));
}

initbuiltin(ctxt: ref Context, shmod: Sh): string
{
	sys = load Sys Sys->PATH;
	sh = shmod;

	myself = load Shellbuiltin "$self";
	if (myself == nil) badmodule(ctxt, "self");

	tk = load Tk Tk->PATH;
	if (tk == nil) badmodule(ctxt, Tk->PATH);

	lock = load Lock Lock->PATH;
	if (lock == nil) badmodule(ctxt, Lock->PATH);
	lock->init();

	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil) badmodule(ctxt, Wmlib->PATH);
	wmlib->init();

	tklock = Semaphore.new();
	if (tklock == nil)
		ctxt.fail("no lock", "tk: cannot make lock");

	ctxt.addbuiltin("tk", myself);
	ctxt.addbuiltin("chan", myself);
	ctxt.addbuiltin("send", myself);

	ctxt.addsbuiltin("tk", myself);
	ctxt.addsbuiltin("recv", myself);
	ctxt.addsbuiltin("alt", myself);
	ctxt.addsbuiltin("tkquote", myself);
	return nil;
}

whatis(nil: ref Sh->Context, nil: Sh, nil: string, nil: int): string
{
	return nil;
}

getself(): Shellbuiltin
{
	return myself;
}

runbuiltin(ctxt: ref Context, nil: Sh,
			cmd: list of ref Listnode, nil: int): string
{
	case (hd cmd).word {
	"tk" =>		return builtin_tk(ctxt, cmd);
	"chan" =>		return builtin_chan(ctxt, cmd);
	"send" =>		return builtin_send(ctxt, cmd);
	}
	return nil;
}

runsbuiltin(ctxt: ref Context, nil: Sh,
			cmd: list of ref Listnode): list of ref Listnode
{
	case (hd cmd).word {
	"tk" =>		return sbuiltin_tk(ctxt, cmd);
	"recv" =>		return sbuiltin_recv(ctxt, cmd);
	"alt" =>		return sbuiltin_alt(ctxt, cmd);
	"tkquote" =>	return sbuiltin_tkquote(ctxt, cmd);
	}
	return nil;
}

builtin_tk(ctxt: ref Context, argv: list of ref Listnode): string
{
	# usage:	tk window _title_ _options_
	#		tk wintitle _winid_ _title_
	#		tk _winid_ _cmd_
	if (tl argv == nil)
		ctxt.fail("usage", "usage: tk (window|wintitle|del|winid) args...");
	argv = tl argv;
	w := (hd argv).word;
	case w {
	"window" =>
		remark(ctxt, string makewin(ctxt, tl argv));

	"wintitle" =>
		argv = tl argv;
		# change the title of a window
		if (len argv != 2 || !isnum((hd argv).word))
			ctxt.fail("usage", "usage: tk wintitle winid title");
		wmlib->taskbar(egetwin(ctxt, hd argv), word(hd tl argv));

	"winctl" =>
		argv = tl argv;
		if (len argv != 2 || !isnum((hd argv).word))
			ctxt.fail("usage", "usage: tk winctl winid cmd");
		wmlib->titlectl(egetwin(ctxt, hd argv), word(hd tl argv));

	"namechan" =>
		argv = tl argv;
		n := len argv;
		if (n < 2 || n > 3 || !isnum((hd argv).word))
			ctxt.fail("usage", "usage: tk namechan winid chan [name]");
		name: string;
		if (n == 3)
			name = word(hd tl tl argv);
		else
			name = word(hd tl argv);
		tk->namechan(egetwin(ctxt, hd argv), egetchan(ctxt, hd tl argv), name);

	"del" =>
		if (len argv < 2)
			ctxt.fail("usage", "usage: tk del id...");
		for (argv = tl argv; argv != nil; argv = tl argv) {
			id := (hd argv).word;
			if (isnum(id))
				delwin(int id);
			delchan(id);
		}
	* =>
		e := tkcmd(ctxt, argv);
		if (e != nil)
			remark(ctxt, e);
		if (e != nil && e[0] == '!')
			return e;
	}
	return nil;
}

remark(ctxt: ref Context, s: string)
{
	if (ctxt.options() & ctxt.INTERACTIVE)
		sys->print("%s\n", s);
}

# create a new window (and its associated channel)
makewin(ctxt: ref Context, argv: list of ref Listnode): int
{
	if (argv == nil)
		ctxt.fail("usage", "usage: tk window title options");

	if (ctxt.drawcontext == nil)
		ctxt.fail("no draw context", sys->sprint("tk: no graphics context available"));

	(title, options) := (word(hd argv), concat(tl argv));
	(top, topchan) := wmlib->titlebar(ctxt.drawcontext.screen, options, title, Wmlib->Appl);
	newid := addwin(top);
	addchan(string newid, topchan);
	return newid;
}

builtin_chan(ctxt: ref Context, argv: list of ref Listnode): string
{
	# create a new channel
	argv = tl argv;
	if (argv == nil)
		ctxt.fail("usage", "usage: chan name....");
	for (; argv != nil; argv = tl argv) {
		name := (hd argv).word;
		if (name == nil || isnum(name))
			ctxt.fail("bad chan", "tk: bad channel name "+q(name));
		if (addchan(name, chan of string) == nil)
			ctxt.fail("bad chan", "tk: channel "+q(name)+" already exists");
	}
	return nil;
}

builtin_send(ctxt: ref Context, argv: list of ref Listnode): string
{
	if (len argv != 3)
		ctxt.fail("usage", "usage: send chan arg");
	argv = tl argv;
	c := egetchan(ctxt, hd argv);
	c <-= word(hd tl argv);
	return nil;
}

sbuiltin_tk(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	# usage:	tk _winid_ _command_
	#		tk window _title_ _options_
	argv = tl argv;
	if (argv == nil)
		ctxt.fail("usage", "tk (window|windows|wid) args");
	case (hd argv).word {
	"window" =>
		return ref Listnode(nil, string makewin(ctxt, tl argv)) :: nil;
	"windows" =>
		return tkwindows(ctxt, tl argv);
	"winids" =>
		ret: list of ref Listnode;
		for (i := 0; i < len wins; i++)
			for (wl := wins[i]; wl != nil; wl = tl wl)
				ret = ref Listnode(nil, string (hd wl).t0) :: ret;
		return ret;
	* =>
		return ref Listnode(nil, tkcmd(ctxt, argv)) :: nil;
	}
}

tkwindows(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	if (ctxt.drawcontext == nil)
		ctxt.fail("no draw context", sys->sprint("tk: no graphics context available"));
	if (argv != nil && (tl argv != nil || (hd argv).word != "-v"))
		ctxt.fail("usage", "usage: tk windows [-v]");
	vflag := argv != nil;
	ret: list of ref Listnode;
	for (wl := tk->windows(ctxt.drawcontext.screen); wl != nil; wl = tl wl)
		if (!vflag || (hd wl).image != nil)
			ret = ref Listnode(nil, string addwin(hd wl)) :: ret;
	return ret;
}

sbuiltin_alt(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	# usage: alt chan ...
	argv = tl argv;
	if (argv == nil)
		ctxt.fail("usage", "usage: alt chan...");
	ca := array[len argv] of chan of string;
	cname := array[len ca] of string;
	i := 0;
	for (; argv != nil; argv = tl argv) {
		ca[i] = egetchan(ctxt, hd argv);
		cname[i] = (hd argv).word;
		i++;
	}
	n := 0;
	v: string;
	if (i == 1)
		v = <-ca[0];
	else
		(n, v) = <-ca;
	
	return ref Listnode(nil, cname[n]) :: ref Listnode(nil, v) :: nil;
}

sbuiltin_recv(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	# usage: recv chan
	if (len argv != 2)
		ctxt.fail("usage", "usage: recv chan");
	c := egetchan(ctxt, hd tl argv);
	return ref Listnode(nil, <-c) :: nil;
}

sbuiltin_tkquote(ctxt: ref Context, argv: list of ref Listnode): list of ref Listnode
{
	if (len argv != 2)
		ctxt.fail("usage", "usage: tkquote arg");
	return ref Listnode(nil, wmlib->tkquote(word(hd tl argv))) :: nil;
}

tkcmd(ctxt: ref Context, argv: list of ref Listnode): string
{
	if (argv == nil || !isnum((hd argv).word))
		ctxt.fail("usage", "usage: tk winid command");

	return tk->cmd(egetwin(ctxt, hd argv), concat(tl argv));
}

hashfn(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i:=0; i<m; i++){
		h = 65599*h+s[i];
	}
	return (h & 16r7fffffff) % n;
}

q(s: string): string
{
	return "'" + s + "'";
}

egetchan(ctxt: ref Context, n: ref Listnode): chan of string
{
	if ((c := getchan(n.word)) == nil)
		ctxt.fail("bad chan", "tk: bad channel name "+ q(n.word));
	return c;
}

# assumes that n.word has been checked and found to be numeric.
egetwin(ctxt: ref Context, n: ref Listnode): ref Tk->Toplevel
{
	wid := int n.word;
	if (wid < 0 || (top := getwin(wid)) == nil)
		ctxt.fail("bad win", "tk: unknown window id " + q(n.word));
	return top;
}

getchan(name: string): chan of string
{
	n := hashfn(name, len chans);
	for (cl := chans[n]; cl != nil; cl = tl cl) {
		(cname, c) := hd cl;
		if (cname == name)
			return c;
	}
	return nil;
}

addchan(name: string, c: chan of string): chan of string
{
	n := hashfn(name, len chans);
	tklock.obtain();
	if (getchan(name) == nil)
		chans[n] = (name, c) :: chans[n];
	tklock.release();
	return c;
}

delchan(name: string)
{
	n := hashfn(name, len chans);
	tklock.obtain();
	ncl: list of (string, chan of string);
	for (cl := chans[n]; cl != nil; cl = tl cl) {
		(cname, nil) := hd cl;
		if (cname != name)
			ncl = hd cl :: ncl;
	}
	chans[n] = ncl;
	tklock.release();
}

addwin(top: ref Tk->Toplevel): int
{
	tklock.obtain();
	id := winid++;
	slot := id % len wins;
	wins[slot] = (id, top) :: wins[slot];
	tklock.release();
	return id;
}

delwin(id: int)
{
	tklock.obtain();
	slot := id % len wins;
	nwl: list of (int, ref Tk->Toplevel);
	for (wl := wins[slot]; wl != nil; wl = tl wl) {
		(wid, nil) := hd wl;
		if (wid != id)
			nwl = hd wl :: nwl;
	}
	wins[slot] = nwl;
	tklock.release();
}

getwin(id: int): ref Tk->Toplevel
{
	slot := id % len wins;
	for (wl := wins[slot]; wl != nil; wl = tl wl) {
		(wid, top) := hd wl;
		if (wid == id)
			return top;
	}
	return nil;
}

word(n: ref Listnode): string
{
	if (n.word != nil)
		return n.word;
	if (n.cmd != nil)
		n.word = sh->cmd2string(n.cmd);
	return n.word;
}

isnum(s: string): int
{
	for (i := 0; i < len s; i++)
		if (s[i] > '9' || s[i] < '0')
			return 0;
	return 1;
}

concat(argv: list of ref Listnode): string
{
	if (argv == nil)
		return nil;
	s := word(hd argv);
	for (argv = tl argv; argv != nil; argv = tl argv)
		s += " " + word(hd argv);
	return s;
}

