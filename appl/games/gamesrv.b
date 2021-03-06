implement Gamesrv;

include "sys.m";
	sys: Sys;
include "readdir.m";
include "styxlib.m";
	styxlib: Styxlib;
	Styxserver, Rmsg, Tmsg, Eperm: import styxlib;
include "lib/multistyx.m";
include "draw.m";
include "arg.m";
include "gamesrv.m";

stderr: ref Sys->FD;
myself: Gamesrv;

ENGINES: con "/dis/games/engines";

Debug: con 0;
Update: adt {
	pick {
	Playerid =>
		clientid:	int;
		playerid:	int;
		name:	string;
	Set =>
		o:		ref Object;
		objid:	int;			# player-specific id
		attr:		ref Attribute;
	Transfer =>
		srcid:	int;			# parent object
		from:	Range;		# range within src to transfer
		dstid:	int;			# destination object
		index:	int;			# insertion point
	Create =>
		objid:	int;
		parentid:	int;
		visibility:	int;
		objtype:	string;
	Delete =>
		parentid:	int;
		r:		Range;
		objs:		array of int;
	Setvisibility =>
		objid:	int;
		visibility:	int;		# set of players that can see it
	Action =>
		s:		string;
		objs:		list of int;
		rest:		string;

	# updates to players file
	Clientid or
	Join =>
		clientid:	int;
		name:	string;
	Leave =>
		clientid:	int;
	Joingame =>			# also sent to individual games
		gameid:	int;
		clientid:	int;
		playerid:	int;
		name:	string;
	Leavegame =>
		gameid:	int;
		playerid:	int;
		name:	string;
	Creategame =>
		gameid:	int;
		name:	string;
		clienttype: string;
	Deletegame =>
		gameid:	int;
	Chat =>
		clientid:	int;
		msg:		string;
	Gametype =>
		clienttype:	string;
		modname:	string;
	}
};

Client: adt {
	id:		int;				# index into clients
	name:	string;
	styxsrv:	ref Styxserver;
	replych:	chan of ref Rmsg;	# buffer

	new:		fn(id: int, styxsrv: ref Styxserver, name: string): ref Client;
	cmd:		fn(client: self ref Client, ofid: ref Openfid, cmd: string): string;
	leave:	fn(client: self ref Client);
	reply:	fn(client: self ref Client, m: ref Rmsg);
};

T: type ref Update;
Queue: adt {
	h, t: list of T; 
	put: fn(q: self ref Queue, s: T);
	get: fn(q: self ref Queue): T;
	isempty: fn(q: self ref Queue): int;
	peek: fn(q: self ref Queue): T;
};

Openfid: adt {
	fidh:		int;			# combination of fid and clientid
	fileid:	int;
	player:	ref Player;		# nil for non-game files.
	client:	ref Client;
	updateq:	ref Queue;
	readreq:	ref Tmsg.Read;
	hungup:	int;

	new:		fn(client: ref Client, fid: int, file: ref File): ref Openfid;
	find:		fn(client: ref Client, fid: int): ref Openfid;
	close:	fn(ofid: self ref Openfid);
};

File: adt {
	id:		int;				# index into files array
	d:		Sys->Dir;
	ofids:	list of ref Openfid;	# list of all fids that are holding this open
	needsupdate:	int;			# updates have been added since last updateall()

	create:	fn(d: Sys->Dir): ref File;
	delete:	fn(f: self ref File);
	hangup:	fn(f: self ref File, client: ref Client);
};

games:	array of ref Game;
clients:	array of ref Client;
files:		array of ref File;
fids:		array of list of ref Openfid;	# hash table
playersf:	ref File;
engines:	list of (string, string);

fPLAYERS,
fGAME,
fNEW: con iota;

MAXPLAYERS: con 31;
GAMEDIR: con "/n/remote";

badmod(p: string)
{
	sys->fprint(stderr, "gamesrv: cannot load %s: %r\n", p);
	sys->raise("fail:bad module");
}

usage()
{
	sys->fprint(stderr, "usage: gamesrv [-l] [-a alg]... [-A] [addr|mntpoint]\n");
	sys->raise("fail:usage");
}

init(ctxt: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);
	myself = load Gamesrv "$self";

	multistyx := load Multistyx Multistyx->PATH;
	if (multistyx == nil)
		badmod(Multistyx->PATH);
	arg := load Arg Arg->PATH;
	if (arg == nil)
		badmod(Arg->PATH);
	arg->init(argv);
	styxlib = multistyx->init();

	doauth := 1;
	local := 0;
	algs: list of string;
	while ((opt := arg->opt()) != 0) {
		case opt {
		'a' =>
			alg := arg->arg();
			if (alg == nil)
				usage();
			algs = alg :: algs;
		'A' =>
			doauth = 0;
		'l' =>
			local = 1;
		* =>
			usage();
		}
	}
	argv = arg->argv();
	arg = nil;
	where: string;
	if (argv != nil) {
		if (tl argv != nil)
			usage();
		where = hd argv;
	}
	initrand();
	initengines();
	fids = array[47] of list of ref Openfid;
	if (local) {
		newclientch := chan of (int, ref Styxserver, string);
		tmsgch := chan of (int, ref Styxserver, ref Tmsg);
		sync := chan of int;
		spawn srv(sync, newclientch, tmsgch);
		<-sync;
		fds := array[2] of ref Sys->FD;
		sys->pipe(fds);
		spawn singlestyx(fds[0], newclientch, tmsgch);
		if (where == nil)
			where = GAMEDIR;
		if (sys->mount(fds[1], where, Sys->MREPL|Sys->MCREATE, nil) == -1) {
			sys->fprint(stderr, "gamesrv: cannot mount on %s: %r\n", where);
			sys->raise("fail:mount failed");		# XXX what about spawned procs?
		}
		sys->print("gamesrv: mounted on %s\n", where);
	} else {
		if (where == nil)
			where = "tcp!*!3242";
		sys->pctl(Sys->FORKNS, nil);
		(newclientch, tmsgch, err) := multistyx->srv(where, 1, algs);
		if (newclientch == nil) {
			sys->fprint(stderr, "gamesrv: cannot start server: %s\n", err);
			sys->raise("fail:error");
		}
		sys->print("gamesrv: listening on %s\n", where);
		sync := chan of int;
		spawn srv(sync, newclientch, tmsgch);
		<-sync;
	}
}

singlestyx(fd: ref Sys->FD, newclientch: chan of (int, ref Styxserver, string),
		tmsgch: chan of (int, ref Styxserver, ref Tmsg))
{
	(tch, ss) := Styxserver.new(fd);
	fd = nil;
	newclientch <-= (0, ss, "me");
	while ((m := <-tch) != nil)
		tmsgch <-= (0, ss, m);
	sys->print("gamesrv: connection unmounted\n");
}
	
srv(sync: chan of int, newclientch: chan of (int, ref Styxserver, string),
		tmsgch: chan of (int, ref Styxserver, ref Tmsg))
{
	sys->pctl(Sys->FORKNS, nil);
	sync <-= 1;
	wfd := sys->open("/prog/" + string sys->pctl(0, nil) + "/wait", Sys->OREAD);
	spawn srv1(newclientch, tmsgch);
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(wfd, buf, len buf);
	sys->print("gamesrv process exited: %s\n", string buf[0:n]);
}

srv1(newclientch: chan of (int, ref Styxserver, string), tmsgch: chan of (int, ref Styxserver, ref Tmsg))
{
	playersf = File.create(styxlib->devdir(nil,
				mkqid(fPLAYERS, 0), "players", big 0, "nobody", 8r666));
	File.create(styxlib->devdir(nil, mkqid(fNEW, 0), "new", big 0, "nobody", 8r666));
	for (;;) alt {
	(srvid, srv, name) := <-newclientch =>
		Client.new(srvid, srv, name);
		updateall();
	(srvid, srv, tmsg) := <-tmsgch =>
		if (tmsg == nil || tagof(tmsg) == tagof(Tmsg.Readerror)) {
			clients[srvid].leave();
			updateall();
		} else
			handletmsg(clients[srvid], tmsg);
	}
}

handletmsg(client: ref Client, tmsg: ref Tmsg)
{
	srv := client.styxsrv;
	pick m := tmsg {
	Nop =>
		srv.reply(ref Rmsg.Nop(m.tag));
	Clone =>
		srv.devclone(m);
	Walk =>
		if ((err := walk(srv, m)) != nil)
			srv.reply(ref Rmsg.Error(m.tag, err));
	Open =>
		c := srv.fidtochan(m.fid);
		if (c.qid.path & Sys->CHDIR) {
			srv.reply(ref Rmsg.Open(m.tag, m.fid, c.qid));
			break;
		}
		f := qid2file(c.qid);
		if (f == nil) {
			srv.reply(ref Rmsg.Error(m.tag, "qid not found"));
			break;
		}
		if (qidkind(c.qid) == fNEW) {
			g := newgame(client);
			Openfid.new(client, m.fid, files[g.fileid]);
			c.qid = files[g.fileid].d.qid;
		} else {
			ofid := Openfid.new(client, m.fid, f);
			err := openfile(ofid);
			if (err != nil) {
				srv.reply(ref Rmsg.Error(m.tag, err));
				ofid.close();
				break;
			}
		}
		srv.reply(ref Rmsg.Open(m.tag, m.fid, c.qid));
		c.open = 1;
		updateall();
	Create =>
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
	Read =>
		c := srv.fidtochan(m.fid);
		if (c.qid.path & Sys->CHDIR) {
			dirread(srv, m);
			break;
		}
		if (!c.open) {
			srv.reply(ref Rmsg.Error(m.tag, "file not open"));
			break;
		}
		ff := Openfid.find(client, m.fid);
		if (ff.readreq != nil)
			srv.reply(ref Rmsg.Error(m.tag, "duplicate read"));
		else {
			ff.readreq = m;
			sendupdate(ff);
		}
	Write =>
		ff := Openfid.find(client, m.fid);
		err := client.cmd(ff, string m.data);
		if (err != nil)
			srv.reply(ref Rmsg.Error(m.tag, err));
		else
			srv.reply(ref Rmsg.Write(m.tag, m.fid, len m.data));
		updateall();
	Clunk =>
		clunked(client, srv.devclunk(m));
		updateall();
	Flush =>
		for (i := 0; i < len files; i++) {
			if (files[i] == nil)
				continue;
			for (ol := files[i].ofids; ol != nil; ol = tl ol) {
				ofid := hd ol;
				if (ofid.client == client && ofid.readreq != nil && ofid.readreq.tag == m.oldtag)
					ofid.readreq = nil;
			}
		}
		srv.reply(ref Rmsg.Flush(m.tag));
	Remove =>
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
	Stat =>
		if ((err := stat(srv, m)) != nil)
			srv.reply(ref Rmsg.Error(m.tag, err));
	Wstat =>
		# XXX eventually allow owner of a game to change its permissions
		srv.reply(ref Rmsg.Error(m.tag, Eperm));
	Attach =>
		srv.devattach(m);
	}
}

clunked(client: ref Client, c: ref Styxlib->Chan)
{
	if (c == nil || !c.open || (c.qid.path & Sys->CHDIR))
		return;
	ofid := Openfid.find(client, c.fid);
	ofid.close();
	if (ofid.player != nil)
		playerleaves(ofid.player);
	f := files[ofid.fileid];
	if (f.ofids == nil && qidkind(f.d.qid) == fGAME) {
		# the game disappears when the last player leaves
		f := files[ofid.fileid];
		if (f.ofids == nil) {
			g := games[qidindex(f.d.qid)];
			if (g != nil) {		# if the game engine hasn't crashed.
				applyupdate(playersf, ref Update.Deletegame(g.id));
				sys->print("clunked(game: %s (id %d), file %ux, client id %d)\n",
					g.name, g.id, f, client.id);
				if (g.request != nil) {
					g.request <-= nil;
					g.request = nil;
				}
				games[g.id] = nil;
			}
			f.delete();
		}
	}
}

Game.hangup(game: self ref Game)
{
	sys->print("game.hangup(%s)\n", game.name);
	f := files[game.fileid];
	for (ofids := f.ofids; ofids != nil; ofids = tl ofids) {
		ofid := hd ofids;
		ofid.player = nil;
		ofid.hungup = 1;
	}
	applyupdate(playersf, ref Update.Deletegame(game.id));
	f.needsupdate = 1;
	if (game.request != nil) {
		game.request <-= nil;
		game.request = nil;
	}
}

Openfid.new(client: ref Client, fid: int, file: ref File): ref Openfid
{
	fidh := fid | (client.id << 16);
	i := fidh % len fids;
	ofid := ref Openfid(fidh, file.id, nil, client, ref Queue, nil, 0);
	fids[i] = ofid :: fids[i];
	file.ofids = ofid :: file.ofids;
	return ofid;
}

Openfid.find(client: ref Client, fid: int): ref Openfid
{
	fidh := fid | (client.id << 16);
	for (ol := fids[fidh % len fids]; ol != nil; ol = tl ol)
		if ((hd ol).fidh == fidh)
			return hd ol;
	return nil;
}
	
Openfid.close(ofid: self ref Openfid)
{
	i := ofid.fidh % len fids;
	newol: list of ref Openfid;
	for (ol := fids[i]; ol != nil; ol = tl ol)
		if (hd ol != ofid)
			newol = hd ol :: newol;
	fids[i] = newol;
	newol = nil;
	for (ol = files[ofid.fileid].ofids; ol != nil; ol = tl ol)
		if (hd ol != ofid)
			newol = hd ol :: newol;
	files[ofid.fileid].ofids = newol;
}

openfile(ofid: ref Openfid): string
{
	err: string;
	q := ofid.updateq;
	f := files[ofid.fileid];
	case qidkind(f.d.qid) {
	fPLAYERS =>
		# all the players
		q.put(ref Update.Clientid(ofid.client.id, ofid.client.name));
		for (i := 0; i < len clients; i++)
			if (clients[i] != nil && i != ofid.client.id)
				q.put(ref Update.Join(i, clients[i].name));
		# all the games
		for (i = 0; i < len games; i++) {
			game := games[i];
			if (game != nil && game.objects != nil) {
				q.put(ref Update.Creategame(game.id, game.name, game.mod->clienttype()));
				# all the clients playing the game
				for (ol := files[game.fileid].ofids; ol != nil; ol = tl ol) {
					ofid := hd ol;
					q.put(ref Update.Joingame(game.id, ofid.client.id, ofid.player.id, nil));
				}
			}
		}
		# all the engines
		for (e := engines; e != nil; e = tl e) {
			(clienttype, modname) := hd e;
			q.put(ref Update.Gametype(clienttype, modname));
		}
		f.needsupdate = 1;
	fGAME =>
		err = newplayer(games[qidindex(f.d.qid)], ofid);
	}
	return err;
}

# a player wants to join in the fun
newplayer(game: ref Game, ofid: ref Openfid): string
{
	if (game.objects == nil)
		return "game not yet active";
	for (i := 0; i < MAXPLAYERS; i++)
		if ((game.playerids & (1 << i)) == 0)
			break;
	if (i == MAXPLAYERS)
		return "too many players";
	client := ofid.client;
	f := files[ofid.fileid];
	for (ol := f.ofids; ol != nil; ol = tl ol)
		if (hd ol != ofid && (hd ol).client == client)
			return "already playing";

	player := ref Player(i, game.id, client.id, nil, nil, nil);
	q := ofid.updateq;
	q.put(ref Update.Playerid(client.id, player.id, client.name));
	# all the clients playing the game
	for (ol = f.ofids; ol != nil; ol = tl ol) {
		ofid := hd ol;
		if (ofid.player != nil)
			q.put(ref Update.Joingame(game.id, ofid.client.id, ofid.player.id, ofid.client.name));
	}
	qrecreateobject(q, player, game.objects[0], nil);
	ofid.player = player;
	game.request <-= ref Rq.Join(player);
	if ((err := <-game.reply) != nil) {
		ofid.player = nil;
		sys->print("join failed: %s\n", err);
		if (game.request == nil)
			game.hangup();
		return err;
	}
	# first player gets the game created
	if (game.playerids == 0)
		applyupdate(playersf, ref Update.Creategame(game.id, game.name, game.mod->clienttype()));
	pmask := 1 << player.id;
	game.playerids |= pmask;
	applyupdate(playersf, ref Update.Joingame(game.id, client.id, player.id, nil));
	applygameupdate(game, ref Update.Joingame(game.id, client.id, player.id, client.name), ~pmask);
	return nil;
}

Blankgame: Game;
newgame(client: ref Client): ref Game
{
	for (i := 0; i < len games; i++)
		if (games[i] == nil)
			break;
	if (i == len games)
		games = (array[len games + 1] of ref Game)[0:] = games;
	g := games[i] = ref Blankgame;
	g.id = i;
	g.request = chan of ref Rq;
	g.reply = chan of string;
	f := File.create(styxlib->devdir(nil, mkqid(fGAME, i), string i, big 0, client.name, 8r666));
	g.fileid = f.id;
	spawn gameproc(g);
	return g;
}

mkqid(kind, i: int): Sys->Qid
{
	return (kind + (i << 4), 0);
}

qidkind(qid: Sys->Qid): int
{
	return qid.path & 16rf;
}

qidindex(qid: Sys->Qid): int
{
	return qid.path >> 4;
}

qid2file(qid: Sys->Qid): ref File
{
	for (i := 0; i < len files; i++) {
		f := files[i];
		if (f != nil && f.d.qid.path == qid.path)
			return f;
	}
	return nil;
}

dirgen(srv: ref Styxserver, c: ref Styxlib->Chan, nil: array of Styxlib->Dirtab, i: int): (int, Sys->Dir)
{
	for (j := 0; j < len files; j++)
		if (files[i] != nil && i-- <= 0)
			return (1, files[j].d);
	d: Sys->Dir;
	return (-1, d);
}

walk(srv: ref Styxserver, m: ref Tmsg.Walk): string
{
	c := srv.fidtochan(m.fid);
	if (c == nil)
		return Styxlib->Ebadfid;
	if ((c.qid.path & Sys->CHDIR) == 0)
		return Styxlib->Enotdir;
	# XXX could speed this up by interpreting names
	# directly.
	for (i := 0; i < len files; i++) {
		f := files[i];
		if (f != nil && f.d.name == m.name) {
			c.qid = f.d.qid;
			c.path = m.name;
			srv.reply(ref Rmsg.Walk(m.tag, m.fid, c.qid));
			return nil;
		}
	}
	return Styxlib->Enotfound;
}

stat(srv: ref Styxserver, m: ref Tmsg.Stat): string
{
	c := srv.fidtochan(m.fid);
	if (c == nil)
		return Styxlib->Ebadfid;
	if (c.qid.path & Sys->CHDIR) {
		srv.reply(ref Rmsg.Stat(m.tag, m.fid,
			styxlib->devdir(c, (Sys->CHDIR, 0), "/", big 0, "nobody", 8r777)));
		return nil;
	}
	f := qid2file(c.qid);
	if (f == nil)
		return "qid not found";
	srv.reply(ref Rmsg.Stat(m.tag, m.fid, f.d));
	return nil;
}

filen(n: int): ref File
{
	for (i := 0; i < len files; i++)
		if (files[i] != nil && n-- <= 0)
			return files[i];
	return nil;
}

dirread(srv: ref Styxserver, m: ref Tmsg.Read)
{
	DIRLEN: import Styxlib;
	data := array[m.count] of byte;
	k := int m.offset / DIRLEN;
	for (n := 0; n + DIRLEN <= m.count; k++) {
		f := filen(k);
		if (f == nil) {
			srv.reply(ref Rmsg.Read(m.tag, m.fid, data[0:n]));
			return;
		}
		styxlib->convD2M(data[n:], f.d);
		n += DIRLEN;
	}
	srv.reply(ref Rmsg.Read(m.tag, m.fid, data[0:n]));
}

updateall()
{
	for (i := 0; i < len files; i++) {
		f := files[i];
		if (f != nil && f.needsupdate) {
			for (ol := f.ofids; ol != nil; ol = tl ol)
				sendupdate(hd ol);
			f.needsupdate = 0;
		}
	}
}

applyupdate(f: ref File, upd: ref Update)
{
	for (ol := f.ofids; ol != nil; ol = tl ol)
		(hd ol).updateq.put(upd);
	f.needsupdate = 1;
}

# send update to players in the game in the needupdate set.
applygameupdate(game: ref Game, upd: ref Update, needupdate: int)
{
	if (needupdate == 0)
		return;
	f := files[game.fileid];
	for (ol := f.ofids; ol != nil; ol = tl ol) {
		ofid := hd ol;
		player := ofid.player;
		if (player != nil && (needupdate & (1 << player.id)))
			queueupdate(ofid.updateq, player, upd);
	}
	f.needsupdate = 1;
}

# transform an outgoing update according to the visibility
# of the object(s) concerned.
# the update concerned has already occurred.
queueupdate(q: ref Queue, p: ref Player, upd: ref Update)
{
	pmask := 1 << p.id;
	game := games[p.gameid];
	pick u := upd {
	Set =>
		if (p.ext(u.o.id) != -1 && (u.attr.needupdate & pmask)) {
			q.put(ref Update.Set(u.o, p.ext(u.o.id), u.attr));
			u.attr.needupdate &= ~pmask;
		} else
			u.attr.needupdate |= pmask;
	Transfer =>
		# if moving from an invisible object, create the objects
		# temporarily in the source object, and then transfer from that.
		# if moving to an invisible object, delete the objects.
		# if moving from invisible to invisible, do nothing.
		src := game.objects[u.srcid];
		dst := game.objects[u.dstid];
		fromvisible := objvisibility(src) & src.visibility & pmask;
		tovisible := objvisibility(dst) & dst.visibility & pmask;
		if (fromvisible || tovisible) {
			# N.B. objects are already in destination object at this point.
			(r, index, srcid) := (u.from, u.index, u.srcid);

			# XXX this scheme is all very well when the parent of src
			# or dst is visible, but not when it's not... in that case
			# we should revert to the old scheme of deleting objects in src
			# or recreating them in dst as appropriate.
			if (!tovisible) {
				# transfer objects to destination, then delete them,
				# so client knows where they've gone.
				q.put(ref Update.Transfer(p.ext(srcid), r, p.ext(u.dstid), 0));
				qdelobjects(q, p, dst, (u.index, u.index + r.end - r.start), 0);
				break;
			}
			if (!fromvisible) {
				# create at the end of source object,
				# then transfer into correct place in destination.
				n := r.end - r.start;
				for (i := 0; i < n; i++) {
					o := dst.children[index + i];
					qrecreateobject(q, p, o, src);
				}
				r = (0, n);
			}
			if (p.ext(srcid) == -1 || p.ext(u.dstid) == -1)
				panic("oh dear 2");
			q.put(ref Update.Transfer(p.ext(srcid), r, p.ext(u.dstid), index));
		}
	Create =>
		dst := game.objects[u.parentid];
		if (objvisibility(dst) & dst.visibility & pmask) {
			playeraddobject(p, game.objects[u.objid]);
			q.put(ref Update.Create(p.ext(u.objid), p.ext(u.parentid), u.visibility, u.objtype));
		}
	Delete =>
		# we can only get this update when all the children are
		# leaf nodes.
		o := game.objects[u.parentid];
		if (objvisibility(o) & o.visibility & pmask) {
			r := u.r;
			extobjs := array[len u.objs] of int;
			for (i := 0; i < len u.objs; i++) {
				extobjs[i] = p.ext(u.objs[i]);
				playerdelobject(p, u.objs[i]);
			}
			q.put(ref Update.Delete(p.ext(o.id), u.r, extobjs));
		}
	Setvisibility =>
		# if the object doesn't exist for this player, don't do anything.
		# else if there are children, check whether they exist, and
		# create or delete them as necessary.
		if (p.ext(u.objid) != -1) {
			o := game.objects[u.objid];
			if (len o.children > 0) {
				visible := u.visibility & pmask;
				made := p.ext(o.children[0].id) != -1;
				if (!visible && made)
					qdelobjects(q, p, o, (0, len o.children), 0);
				else if (visible && !made)
					for (i := 0; i < len o.children; i++)
						qrecreateobject(q, p, o.children[i], nil);
			}
			q.put(ref Update.Setvisibility(p.ext(u.objid), u.visibility));
		}
	Action =>
		s := u.s;
		for (ol := u.objs; ol != nil; ol = tl ol)
			s += " " + string p.ext(hd ol);
		s += " " + u.rest;
		q.put(ref Update.Action(s, nil, nil));
	* =>
		q.put(upd);
	}
}

# queue deletions for o; we pretend to the client that
# the deletions are at index.
qdelobjects(q: ref Queue, p: ref Player, o: ref Object, r: Range, index: int)
{
	if (r.start >= r.end)
		return;
	children := o.children;
	extobjs := array[r.end - r.start] of int;
	for (i := r.start; i < r.end; i++) {
		o := children[i];
		qdelobjects(q, p, o, (0, len o.children), 0);
		extobjs[i - r.start] = p.ext(o.id);
		playerdelobject(p, o.id);
	}
	q.put(ref Update.Delete(p.ext(o.id), (index, index + (r.end - r.start)), extobjs));
}

File.create(d: Sys->Dir): ref File
{
	for (i := 0; i < len files; i++)
		if (files[i] == nil)
			break;
	if (i == len files) {
		newfiles := array[len files + 1] of ref File;
		newfiles[0:] = files;
		files = newfiles;
	}
	f := files[i] = ref File(i, d, nil, 0);
	return f;
}

File.delete(f: self ref File)
{
	files[f.id] = nil;
}

File.hangup(f: self ref File, client: ref Client)
{
	for (ofids := f.ofids; ofids != nil; ofids = tl ofids)
		if ((hd ofids).client == client)
			(hd ofids).hungup = 1;
	f.needsupdate = 1;
}

# parent visibility now allows o to be seen, so recreate
# it for the player. (if parent is non-nil, pretend we're creating it there)
qrecreateobject(q: ref Queue, p: ref Player, o: ref Object, parent: ref Object)
{
	playeraddobject(p, o);
	parentid := o.parentid;
	if (parent != nil)
		parentid = parent.id;
	q.put(ref Update.Create(p.ext(o.id), p.ext(parentid), o.visibility, o.objtype));
	recreateattrs(q, p, o);
	if (o.visibility & (1 << p.id)) {
		a := o.children;
		for (i := 0; i < len a; i++)
			qrecreateobject(q, p, a[i], nil);
	}
}

recreateattrs(q: ref Queue, p: ref Player, o: ref Object)
{
	a := o.attrs.a;
	for (i := 0; i < len a; i++) {
		for (al := a[i]; al != nil; al = tl al) {
			attr := hd al;
			q.put(ref Update.Set(o, p.ext(o.id), attr));
		}
	}
}

# send the client as many updates as we can fit in their read request
# (if there are some updates to send and there's an outstanding read request)
sendupdate(ofid: ref Openfid)
{
	game: ref Game;
	if (ofid.readreq == nil || (ofid.updateq.isempty() && !ofid.hungup))
		return;
	client := ofid.client;
	m := ofid.readreq;
	q := ofid.updateq;
	if (ofid.hungup) {
		client.reply(ref Rmsg.Read(m.tag, m.fid, nil));
		q.h = q.t = nil;
		return;
	}
	data := array[m.count] of byte;
	nb := 0;
	pmask := 0;
	if (ofid.player != nil) {
		pmask = 1 << ofid.player.id;
		game = games[ofid.player.gameid];
	}
	for (; !q.isempty(); q.get()) {
		upd := q.peek();
		pick u := upd {
		Set =>
			if ((objvisibility(u.o) & u.attr.visibility & pmask) == 0) {
				u.attr.needupdate |= pmask;
				continue;
			}
		}
		d := array of byte update2s(upd);
		if (len d + nb > len data)
			break;
		data[nb:] = d;
		nb += len d;
	}
	data = data[0:nb];
	err := "";
	if (nb == 0) {
		if (q.isempty())
			return;
		err = "short read";
	}
	if (err != nil)
		client.reply(ref Rmsg.Error(m.tag, err));
	else
		client.reply(ref Rmsg.Read(m.tag, m.fid, data));
	ofid.readreq = nil;
}

# an object's visibility is the intersection
# of the visibility of all its parents.
objvisibility(o: ref Object): int
{
	game := games[o.gameid];
	visibility := ~0;
	for (id := o.parentid; id != -1; id = o.parentid) {
		o = game.objects[id];
		visibility &= o.visibility;
	}
	return visibility;
}

Client.new(id: int, styxsrv: ref Styxserver, name: string): ref Client
{
	if (id >= len clients) {
		newclients := array[id + 1] of ref Client;
		newclients[0:] = clients;
		clients = newclients;
	}

	if (clients[id] != nil)
		panic(sys->sprint("client id %d already in use (by '%s')\n", id, clients[id].name));
	client := ref Client;
	client.name = name;
	client.replych = chan of ref Rmsg;
	client.styxsrv = styxsrv;
	client.id = id;
	clients[id] = client;
	spawn replyproc(client.styxsrv, client.replych);
	applyupdate(playersf, ref Update.Join(client.id, client.name));
	return client;
}

replyproc(styxsrv: ref Styxserver, replych: chan of ref Rmsg)
{
	procname("reply");
	for (;;) {
		m := <-replych;
		if (m == nil)
			exit;
		styxsrv.reply(m);
	}
}

Client.reply(client: self ref Client, m: ref Rmsg)
{
	client.replych <-= m;
}

Client.leave(client: self ref Client)
{
	sys->print("client %d leaving\n", client.id);
	for (cl := client.styxsrv.chanlist(); cl != nil; cl = tl cl)
		clunked(client, hd cl);

	client.replych <-= nil;
	clients[client.id] = nil;
	applyupdate(playersf, ref Update.Leave(client.id));
}

# process a client's command; return a non-nil string on error.
Client.cmd(client: self ref Client, ofid: ref Openfid, cmd: string): string
{
	err: string;
	f := files[ofid.fileid];
	qid := f.d.qid;
	if (ofid.hungup)
		return "hung up";
	if (cmd == nil) {
		f.hangup(client);
		sys->print("hanging up client %d, file %s\n", client.id, f.d.name);
		return nil;
	}
	case qidkind(qid) {
	fGAME =>
		game := games[qidindex(qid)];
		if (ofid.player == nil)
			err = inactivegamecmd(client, game, ofid, cmd);
		else {
			game.request <-= ref Rq.Command(ofid.player, cmd);
			err = <-game.reply;
			if (game.request == nil)
				game.hangup();
		}
	fPLAYERS =>
		for (i := 0; i < len cmd; i++)
			if (cmd[i] == '\n')
				break;
		applyupdate(playersf, ref Update.Chat(client.id, cmd[0:i]));
	* =>
		err = "invalid command" + string qid.path;
	}
	return err;
}

gameproc(game: ref Game)
{
	wfd := sys->open("/prog/" + string sys->pctl(0, nil) + "/wait", Sys->OREAD);
	spawn gameproc1(game);
	buf := array[Sys->ATOMICIO] of byte;
	n := sys->read(wfd, buf, len buf);
	sys->print("gamesrv: game '%s' exited: %s\n", game.name, string buf[0:n]);
	game.request = nil;
	game.reply <-= "game exited";
}

gameproc1(game: ref Game)
{
	for (;;) {
		rq := <-game.request;
		if (rq == nil)
			break;
		reply := "";
		pick r := rq {
		Init =>
			reply = game.mod->init(game, myself);
		Join =>
			reply = game.mod->join(r.player);
		Command =>
			reply = game.mod->command(r.player, r.cmd);
		Leave =>
			game.mod->leave(r.player);
		}
		game.reply <-= reply;
	}
	sys->print("gamesrv: game '%s' exiting\n", game.name);
}

inactivegamecmd(client: ref Client, g: ref Game, ofid: ref Openfid, cmd: string): string
{
	(n, toks) := sys->tokenize(cmd, " \n");
	if (n != 2 || hd toks != "create")
		return "bad command usage";
	title := hd tl toks;
	# protect against dastardly deeds.
	for (i := 0; i < len title; i++)
		if (title[i] == '/')
			return "dastard";
	path := ENGINES + "/" + title + ".dis";
	if ((g.mod = load Gamemodule path) == nil) {
		sys->fprint(stderr, "gamesrv: cannot load game '%s': %r\n", path);
		return "cannot load game module";
	}
	g.objects = array[] of {ref Object(0, Attributes.new(), ~0, -1, nil, g.id, nil)};
	g.name = title;
	g.request <-= ref Rq.Init();
	err := <-g.reply;
	if (err != nil || (err = newplayer(g, ofid)) != nil) {
		g.mod = nil;
		g.objects = nil;
		return err;
	}
	return nil;
}

makespace(objects: array of ref Object,
		freelist: list of int): (array of ref Object, list of int)
{
	if (freelist == nil) {
		na := array[len objects + 10] of ref Object;
		na[0:] = objects;
		for (j := len na - 1; j >= len objects; j--)
			freelist = j :: freelist;
		objects = na;
	}
	return (objects, freelist);
}

# as a special case, if parent is nil, we use the root object.
Game.newobject(game: self ref Game, parent: ref Object, visibility: int, objtype: string): ref Object
{
	if (game.freelist == nil)
		(game.objects, game.freelist) =
			makespace(game.objects, game.freelist);
	id := hd game.freelist;
	game.freelist = tl game.freelist;

	if (parent == nil)
		parent = game.objects[0];
	obj := ref Object(id, Attributes.new(), visibility, parent.id, nil, game.id, objtype);

	n := len parent.children;
	newchildren := array[n + 1] of ref Object;
	newchildren[0:] = parent.children;
	newchildren[n] = obj;
	parent.children = newchildren;
	game.objects[id] = obj;
	applygameupdate(game, ref Update.Create(id, parent.id, visibility, objtype), ~0);
	if (Debug)
		sys->print("new %d, parent %d, visibility %s\n", obj.id, parent.id, players2s(game, visibility));
	return obj;
}

Game.action(game: self ref Game, cmd: string,
			objs: list of int, rest: string, whoto: int)
{
	applygameupdate(game, ref Update.Action(cmd, objs, rest), whoto);
}

Game.player(game: self ref Game, id: int): ref Player
{
	for (ol := files[game.fileid].ofids; ol != nil; ol = tl ol)
		if ((hd ol).player != nil && (hd ol).player.id == id)
			return (hd ol).player;
	return nil;
}

#Game.save(game: self ref Game, fd: ref Sys->FD)
#{
#	iob := bufio->fopen(fd, Sys->OWRITE);
# 	iob.puts(str->quoted("game" :: 

Player.ext(player: self ref Player, id: int): int
{
	obj2ext := player.obj2ext;
	if (id >= len obj2ext || id < 0)
		return -1;
	return obj2ext[id];
}

Player.obj(player: self ref Player, ext: int): ref Object
{
	if (ext < 0 || ext >= len player.ext2obj)
		return nil;
	return player.ext2obj[ext];
}

# allocate an object in a player's map.
playeraddobject(p: ref Player, o: ref Object)
{
	if (p.freelist == nil)
		(p.ext2obj, p.freelist) = makespace(p.ext2obj, p.freelist);
	ext := hd p.freelist;
	p.freelist = tl p.freelist;

	if (o.id >= len p.obj2ext) {
		oldmap := p.obj2ext;
		newmap := array[o.id + 10] of int;
		newmap[0:] = oldmap;
		for (i := len oldmap; i < len newmap; i++)
			newmap[i] = -1;
		p.obj2ext = newmap;
	}
	p.obj2ext[o.id] = ext;
	p.ext2obj[ext] = o;
	if (Debug)
		sys->print("addobject player %d, internal %d, external %d\n", p.id, o.id, ext);
}

# delete an object from a player's map.
playerdelobject(player: ref Player, id: int)
{
	if (id >= len player.obj2ext) {
		sys->fprint(stderr, "gamesrv: bad delobject (player %d, id %d, len obj2ext %d)\n",
				player.id, id, len player.obj2ext);
		return;
	}
	ext := player.obj2ext[id];
	player.ext2obj[ext] = nil;
	player.obj2ext[id] = -1;
	player.freelist = ext :: player.freelist;
	if (Debug)
		sys->print("delobject player %d, internal %d, external %d\n", player.id, id, ext);
}

playerleaves(player: ref Player)
{
	sys->print("player %d leaving game %d\n", player.id, player.gameid);
	game := games[player.gameid];
	game.request <-= ref Rq.Leave(player);
	<-game.reply;
	if (game.request == nil) {
		sys->print("player leaving\n");
		game.hangup();
	} else {
		game.playerids &= ~(1 << player.id);
		upd := ref Update.Leavegame(player.gameid, player.id, player.name());
		applyupdate(playersf, upd);
		applygameupdate(game, upd, ~0);
	}
}

Player.name(player: self ref Player): string
{
	return clients[player.clientid].name;
}

Player.hangup(player: self ref Player)
{
	files[games[player.gameid].fileid].hangup(clients[player.clientid]);
}

Object.delete(o: self ref Object)
{
	game := games[o.gameid];
	if (o.parentid != -1) {
		parent := game.objects[o.parentid];
		siblings := parent.children;
		for (i := 0; i < len siblings; i++)
			if (siblings[i] == o)
				break;
		if (i == len siblings)
			panic("object " + string o.id + " not found in parent");
		parent.deletechildren((i, i+1));
	} else
		sys->fprint(stderr, "gamesrv: cannot delete root object\n");
	o.id = -1;
}

Object.deletechildren(parent: self ref Object, r: Range)
{
	if (len parent.children == 0)
		return;
	game := games[parent.gameid];
	n := r.end - r.start;
	objs := array[r.end - r.start] of int;
	children := parent.children;
	for (i := r.start; i < r.end; i++) {
		o := children[i];
		objs[i - r.start] = o.id;
		o.deletechildren((0, len o.children));
		game.objects[o.id] = nil;
		game.freelist = o.id :: game.freelist;
		o.id = -1;
	}
	children[r.start:] = children[r.end:];
	for (i = len children - n; i < len children; i++)
		children[i] = nil;
	if (n < len children)
		parent.children = children[0:len children - n];
	else
		parent.children = nil;

	if (Debug) {
		sys->print("+del from %d, range [%d %d], objs: ", parent.id, r.start, r.end);
		for (i = 0; i < len objs; i++)
			sys->print("%d ", objs[i]);
		sys->print("\n");
	}
	applygameupdate(game, ref Update.Delete(parent.id, r, objs), ~0);
}

# move a range of objects from src and insert them at index in dst.
Object.transfer(src: self ref Object, r: Range, dst: ref Object, index: int)
{
	if (index == -1)
		index = len dst.children;
	if (src == dst && index >= r.start && index <= r.end)
		return;
	n := r.end - r.start;
	objs := src.children[r.start:r.end];
	newchildren := array[len src.children - n] of ref Object;
	newchildren[0:] = src.children[0:r.start];
	newchildren[r.start:] = src.children[r.end:];
	src.children = newchildren;

	if (Debug) {
		sys->print("+transfer from %d[%d,%d] to %d[%d], objs: ",
			src.id, r.start, r.end, dst.id, index);
		for (x := 0; x < len objs; x++)
			sys->print("%d ", objs[x].id);
		sys->print("\n");
	}

	nindex := index;

	# if we've just removed some cards from the destination,
	# then adjust the destination index accordingly.
	if (src == dst && nindex > r.start) {
		if (nindex < r.end)
			nindex = r.start;
		else
			nindex -= n;
	}
	newchildren = array[len dst.children + n] of ref Object;
	newchildren[0:] = dst.children[0:index];
	newchildren[nindex + n:] = dst.children[nindex:];
	newchildren[nindex:] = objs;
	dst.children = newchildren;

	for (i := 0; i < len objs; i++)
		objs[i].parentid = dst.id;

	game := games[src.gameid];
	applygameupdate(game,
		ref Update.Transfer(src.id, r, dst.id, index),
		~0);
}

# visibility is only set when the attribute is newly created.
Object.setattr(o: self ref Object, name, val: string, visibility: int)
{
	(changed, attr) := o.attrs.set(name, val, visibility);
	if (changed) {
		attr.needupdate = ~0;
		applygameupdate(games[o.gameid], ref Update.Set(o, o.id, attr), objvisibility(o));
	}
}

Object.getattr(o: self ref Object, name: string): string
{
	attr := o.attrs.get(name);
	if (attr == nil)
		return nil;
	return attr.val;
}

# set visibility of an object - reveal any uncovered descendents
# if necessary.
Object.setvisibility(o: self ref Object, visibility: int)
{
	if (o.visibility == visibility)
		return;
	o.visibility = visibility;
	applygameupdate(games[o.gameid], ref Update.Setvisibility(o.id, visibility), objvisibility(o));
}

Object.setattrvisibility(o: self ref Object, name: string, visibility: int)
{
	attr := o.attrs.get(name);
	if (attr == nil) {
		sys->fprint(stderr, "gamesrv: setattrvisibility, no attribute '%s', id %d\n", name, o.id);
		return;
	}
	if (attr.visibility == visibility)
		return;
	# send updates to anyone that has needs updating,
	# is in the new visibility list, but not in the old one.
	ovisibility := objvisibility(o);
	before := ovisibility & attr.visibility;
	after := ovisibility & visibility;
	attr.visibility = visibility;
	applygameupdate(games[o.gameid], ref Update.Set(o, o.id, attr), ~before & after);
}

# convert an Update adt to a string.
update2s(upd: ref Update): string
{
	s: string;
	pick u := upd {
	Create =>
		objtype := u.objtype;
		if (objtype == nil)
			objtype = "nil";
		s = sys->sprint("create %d %d %d %s\n", u.objid, u.parentid, u.visibility, objtype);
	Transfer =>
		# tx src dst dstindex start end
		if (u.srcid == -1 || u.dstid == -1)
			panic("oh dear");
		s = sys->sprint("tx %d %d %d %d %d\n",
			u.srcid, u.dstid, u.from.start, u.from.end, u.index);
	Delete =>
		s = sys->sprint("del %d %d %d", u.parentid, u.r.start, u.r.end);
		for (i := 0; i < len u.objs; i++)
			s += " " + string u.objs[i];
		s[len s] = '\n';
	Set =>
		s = sys->sprint("set %d %s %s\n", u.objid, u.attr.name, u.attr.val);
	Setvisibility =>
		s = sys->sprint("vis %d %d\n", u.objid, u.visibility);
	Action =>
		s = u.s + "\n";
	Playerid =>
		s = sys->sprint("playerid %d %d %s\n", u.clientid, u.playerid, u.name);
	Clientid =>
		s = sys->sprint("clientid %d %s\n", u.clientid, u.name);
	Join =>
		s = sys->sprint("join %d %s\n", u.clientid, u.name);
	Leave =>
		s = sys->sprint("leave %d\n", u.clientid);
	Joingame =>
		s = sys->sprint("joingame %d %d %d %s\n", u.gameid, u.clientid, u.playerid, u.name);
	Leavegame =>
		s = sys->sprint("leavegame %d %d %s\n", u.gameid, u.playerid, u.name);
	Creategame =>
		s = sys->sprint("creategame %d %s %s\n", u.gameid, u.name, u.clienttype);
	Deletegame =>
		s = sys->sprint("delgame %d\n", u.gameid);
	Chat =>
		s = sys->sprint("chat %d %s\n", u.clientid, u.msg);
	Gametype =>
		s = sys->sprint("gametype %s %s\n", u.clienttype, u.modname);
	* =>
		sys->fprint(stderr, "unknown update tag %d\n", tagof(upd));
	}
	return s;
}

Queue.put(q: self ref Queue, s: T)
{
	q.t = s :: q.t;
}

Queue.get(q: self ref Queue): T
{
	s: T;
	if(q.h == nil){
		q.h = revlist(q.t);
		q.t = nil;
	}
	if(q.h != nil){
		s = hd q.h;
		q.h = tl q.h;
	}
	return s;
}

Queue.peek(q: self ref Queue): T
{
	s: T;
	if (q.isempty())
		return s;
	s = q.get();
	q.h = s :: q.h;
	return s;
}

Queue.isempty(q: self ref Queue): int
{
	return q.h == nil && q.t == nil;
}

revlist(ls: list of T) : list of T
{
	rs: list of T;
	for (; ls != nil; ls = tl ls)
		rs = hd ls :: rs;
	return rs;
}

Attributes.new(): ref Attributes
{
	return ref Attributes(array[7] of list of ref Attribute);
}

Attributes.get(attrs: self ref Attributes, name: string): ref Attribute
{
	for (al := attrs.a[strhash(name, len attrs.a)]; al != nil; al = tl al)
		if ((hd al).name == name)
			return hd al;
	return nil;
}

# return (haschanged, attr)
Attributes.set(attrs: self ref Attributes, name, val: string, visibility: int): (int, ref Attribute)
{
	h := strhash(name, len attrs.a);
	for (al := attrs.a[h]; al != nil; al = tl al) {
		attr := hd al;
		if (attr.name == name) {
			if (attr.val == val)
				return (0, attr);
			attr.val = val;
			return (1, attr);
		}
	}
	attr := ref Attribute(name, val, visibility, ~0);
	attrs.a[h] = attr :: attrs.a[h];
	return (1, attr);
}

initengines()
{
	readdir := load Readdir Readdir->PATH;
	if (readdir == nil) {
		sys->fprint(stderr,  "gamesrv: cannot load %s: %r\n", Readdir->PATH);
		return;
	}
	(d, n) := readdir->init(ENGINES, Readdir->NAME|Readdir->COMPACT);
	for (i := 0; i < len d; i++) {
		mod := d[i].name;
		if (len mod < 5 || mod[len mod - 4:] != ".dis")
			continue;
		m := load Gamemodule ENGINES + "/" + mod;
		if (m == nil) {
			sys->fprint(stderr, "gamesrv: cannot load engine %s: %r\n", mod);
			continue;
		}
		engines = (m->clienttype(), mod[0:len mod - 4]) :: engines;
		m = nil;
	}
	sys->print("found %d game engines\n", len engines);
}

# non-blocking reply to read request, in case client has gone away.
readreply(reply: Sys->Rread, data: array of byte, err: string)
{
	alt {
	reply <-= (data, err) =>;
	* =>;
	}
}

# non-blocking reply to write request, in case client has gone away.
writereply(reply: Sys->Rwrite, count: int, err: string)
{
	alt {
	reply <-= (count, err) =>;
	* =>;
	}
}

# from Aho Hopcroft Ullman
strhash(s: string, n: int): int
{
	h := 0;
	m := len s;
	for(i := 0; i<m; i++){
		h = 65599 * h + s[i];
	}
	return (h & 16r7fffffff) % n;
}

panic(s: string)
{
	games[0].show(nil);
	sys->fprint(stderr, "panic: %s\n", s);
	sys->raise("panic");
}

randbits: chan of int;

initrand()
{
	randbits = chan of int;
	spawn randproc();
}

randproc()
{
	fd := sys->open("/dev/notquiterandom", Sys->OREAD);
	if (fd == nil) {
		sys->print("cannot open /dev/random: %r\n");
		exit;
	}
	randbits <-= sys->pctl(0, nil);
	buf := array[1] of byte;
	while ((n := sys->read(fd, buf, len buf)) > 0) {
		b := buf[0];
		for (i := byte 1; i != byte 0; i <<= 1)
			randbits <-= (b & i) != byte 0;
	}
}

rand(n: int): int
{
	x: int;
	for (nbits := 0; (1 << nbits) < n; nbits++)
		x ^= <-randbits << nbits;
	x ^= <-randbits << nbits;
	x &= (1 << nbits) - 1;
	i := 0;
	while (x >= n) {
		x ^= <-randbits << i;
		i = (i + 1) % nbits;
	}
	return x;
}

players2s(game: ref Game, players: int): string
{
	all := (1 << MAXPLAYERS) - 1;
	if ((players & all) == all)
		return "[all]";
	if ((players & all) == 0)
		return "[none]";
	s := "[";
	comma := "";
	for ((p, i) := (0, 1); i != 512; (p, i) = (p+1, i<<1)) {
		if (players & i) {
			s += comma + string p;
			comma = ",";
		}
	}
	s[len s] = ']';
	return s;
}

Game.show(game: self ref Game, p: ref Player)
{
	sys->print("**************** all objects:\n");
	showobject(game, game.objects[0], p, 0, ~0);
	if (p == nil) {
		f := files[game.fileid];
		for (ol := f.ofids; ol != nil; ol = tl ol) {
			p := (hd ol).player;
			sys->print("player %d: ext->obj ", p.id);
			for (j := 0; j < len p.ext2obj; j++)
				if (p.ext2obj[j] != nil)
					sys->print("%d->%d[%d] ", j, p.ext2obj[j].id, p.ext(p.ext2obj[j].id));
			sys->print("\n");
		}
	}
}

spc(n: int): string
{
	if (n == 0)
		return nil;
	return sys->sprint("%*s", n, "");
}

check(o: ref Object)
{
	n := 0;
	if (o.parentid != -1) {
		parent := games[0].objects[o.parentid];
		for (i := 0; i < len parent.children; i++)
			if (o == parent.children[i])
				n++;
		if (n != 1)
			panic("integrity violation");
	}
	for (i := 0; i < len o.children; i++)
		check(o.children[i]);
}

showobject(game: ref Game, o: ref Object, p: ref Player, depth: int, visibility: int)
{
	ext := o.id;
	pmask := ~0;
	if (p != nil) {
		ext = p.ext(o.id);
		pmask = 1 << p.id;
	}
	if (o.parentid != -1) {
		parent := game.objects[o.parentid];
		n := 0;
		for (i := 0; i < len parent.children; i++)
			if (o == parent.children[i])
				n++;
		if (n != 1)
			sys->print("%s%d. ******** integrity violation, %d parent mentions\n", spc(depth*2),
					o.id, n);
	}
	if (ext != -1) {
		sys->print("%s%d. [%d] %d children; %s %#ux\n", spc(depth*2), ext, o.id, len o.children,
				players2s(game, o.visibility), o);
		for (j := 0; j < len o.attrs.a; j++)
			for (al := o.attrs.a[j]; al != nil; al = tl al) {
				attr := hd al;
				if (p == nil || (visibility & attr.visibility & pmask)) {
					sys->print("%s%s=%s %s\n", spc((depth+1)*2),
						attr.name, attr.val, players2s(game, attr.visibility));
				} else
					sys->print("%s*%s=%s %s\n", spc((depth+1)*2),
						attr.name, attr.val, players2s(game, attr.visibility));
			}
	} else
		sys->print("%sno %d\n", spc(depth*2), o.id);
	for (i := 0; i < len o.children; i++)
		showobject(game, o.children[i], p, depth + 1, o.visibility & visibility);
}

procname(s: string)
{
#	sys->procname(sys->procname(nil) + " " + s);
}

