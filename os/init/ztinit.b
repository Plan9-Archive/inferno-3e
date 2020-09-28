implement Init;
#
# init program for Ziatech ZT5512 BSP
#
include "sys.m";
sys: Sys;
FD, Connection, sprint, Dir: import sys;
print, fprint, open, bind, mount, dial, sleep, read: import sys;

include "security.m";
auth:	Auth;

include "draw.m";
draw: Draw;
Context: import draw;

include "keyring.m";
kr: Keyring;

Init: module
{
	init:	fn();
};

Logon: module
{
	init:	fn(ctxt: ref Context, argv: list of string);
};

rootfs(server: string): int
{
	ok, n: int;
	c: Connection;

	(ok, c) = dial("tcp!" + server + "!6666", nil);
	if(ok < 0)
		return -1;

	sys->print("Connected ...");
	if(kr != nil && auth != nil){
		err: string;
		sys->print("Authenticate ...");
		ai := kr->readauthinfo("/nvfs/default");
		if(ai == nil){
			sys->print("readauthinfo /nvfs/default failed: %r\n");
			sys->print("trying mount as `nobody'\n");
		}
		(c.dfd, err) = auth->client("none", ai, c.dfd);
		if(c.dfd == nil){
			sys->print("authentication failed: %s\n", err);
			return -1;
		}
	}

	sys->print("mount ...");

	c.cfd = nil;
	n = mount(c.dfd, "/", sys->MREPL, "");
	if(n > 0)
		return 0;
	return -1;
}

Bootpreadlen: con 128;

init()
{
	spec: string;

	sys = load Sys Sys->PATH;
	kr = load Keyring Keyring->PATH;
	auth = load Auth Auth->PATH;
	if(auth != nil)
		auth->init();

	sys->print("**\n** Inferno\n** Vita Nuova\n**\n");

	sys->print("Setup boot net services ...\n");
	
	#
	# Setup what we need to call a server and
	# Authenticate
	#
	bind("#l", "/net", sys->MREPL);
	bind("#I", "/net", sys->MAFTER);
	bind("#c", "/dev", sys->MAFTER);
	nvramfd := sys->open("#H/hd0nvram", sys->ORDWR);
	if(nvramfd != nil){
		spec = sys->sprint("#F%d", nvramfd.fd);
		if(bind(spec, "/nvfs", sys->MAFTER) < 0)
			print("init: bind %s: %r\n", spec);
	}

	setsysname();

	sys->print("bootp ...");

	fd := open("/net/ipifc/clone", sys->OWRITE);
	if(fd == nil) {
		print("init: open /net/ipifc/clone: %r\n");
		exit;
	}
	cfg := array of byte "bind ether ether0";
	if(sys->write(fd, cfg, len cfg) != len cfg) {
		sys->print("could not bind interface: %r\n");
		exit;
	}
	cfg = array of byte "bootp";
	if(sys->write(fd, cfg, len cfg) != len cfg) {
		sys->print("could not bootp: %r\n");
		exit;
	}

	fd = open("/net/bootp", sys->OREAD);
	if(fd == nil) {
		print("init: open /net/bootp: %r");
		exit;
	}

	buf := array[Bootpreadlen] of byte;
	nr := read(fd, buf, len buf);
	fd = nil;
	if(nr <= 0) {
		print("init: read /net/bootp: %r");
		exit;
	}

	(ntok, ls) := sys->tokenize(string buf, " \t\n");
	while(ls != nil) {
		if(hd ls == "fsip"){
			ls = tl ls;
			break;
		}
		ls = tl ls;
	}
	if(ls == nil) {
		print("init: server address not in bootp read");
		exit;
	}

	srv := hd ls;
	sys->print("server %s\nConnect ...\n", srv);

	retrycount := 0;
	while(rootfs(srv) < 0 && retrycount++ < 5)
		sleep(1000);

	sys->print("done\n");

	#
	# default namespace
	#
	bind("#c", "/dev", sys->MREPL);			# console
	if(spec != nil)
		bind(spec, "/nvfs", sys->MBEFORE|sys->MCREATE);	# our keys
	bind("#I", "/net", sys->MBEFORE);		# TCP/IP
	bind("#p", "/prog", sys->MREPL);		# prog device
	bind("#b", "/dev",sys->MBEFORE);		# devdbg devices
	bind("#H", "/dev",sys->MBEFORE);		# ATA Hard Drive
	bind("#t", "/dev", sys->MBEFORE);		# Serial Ports
	bind("#L", "/dev", sys->MBEFORE);		# Parallel Port
	bind("#f", "/dev", sys->MBEFORE);		# Floppy Drive
	bind("#r", "/dev", sys->MBEFORE);		# RTC Clock
	bind("#s", "/chan", sys->MREPL);		# Global Chan
	bind("#Z", "/dev", sys->MBEFORE);		# Ziatech Sys Registers
	bind("#F", "/dev", sys->MBEFORE);		# Flash
	bind("#a", "/dev", sys->MBEFORE);		# beep

	sys->print("clock...\n");
	setclock();

	# Turn on green LED's and give us a warm fuzzy

	ledfd := sys->open("/dev/ledctl", Sys->OWRITE);
	sys->fprint(ledfd,"usr1 green");
	sys->fprint(ledfd,"usr2 green");
	ledfd = nil;

	sys->print("logon...\n");

	stdin := sys->fildes(0);
	rbuf := array[128] of byte;
	shell := 1;
if (0) {
	loop: for (;;) {
		sys->print("run [shell, logon]:");
		n := sys->read(stdin, rbuf, len rbuf);
		if (n <= 0)
			continue;
		if (rbuf[n-1] == byte '\n')
			n--;
		(nil, choice) := sys->tokenize(string rbuf[0:n], "\t ");
		if (choice == nil)
			continue;
		opt := hd choice;
		case opt {
			* =>
				sys->print("\ninvalid option: '%s'\n", opt);
				break;
			"shell" =>
				shell = 1;
				break loop;
			"logon" =>
				shell = 0;
				break loop;
		}
	}
}
	if (shell)
		logon := load Logon "/dis/sh.dis";
	else {
		logon = load Logon "/dis/wm/logon.dis";
		if(logon == nil) {
			print("init: load /dis/wm/logon.dis: %r");
			logon = load Logon "/dis/sh.dis";
		}
	}
	if (logon == nil) {
		print("init: load /dis/sh.dis: %r");
		exit;
	}
	dc: ref Context;
	spawn logon->init(dc, nil);
}

setclock()
{
	# Shouldn't we try to set it off the Real-Time Clock?
	rtcfd := sys->open("/dev/rtc", sys->OREAD);

	if (rtcfd == nil) {
		print("init: read /dev/rtc: %r");
		return;
	}

	rtcread := array[16] of byte;
	sys->read(rtcfd, rtcread, 16);

	fd := sys->open("/dev/time", sys->OWRITE);
	if (fd == nil) {
		print("init: open /dev/time: %r");
		return;
	}

	# Time is kept as microsecs, rtc is in secs
	b := array of byte sprint("%s000000", string rtcread);
	if (sys->write(fd, b, len b) != len b)
		print("init: write /dev/time: %r");
}

#
# Set system name from nvram
#
setsysname()
{
	fd := open("/nvfs/ID", sys->OREAD);
	if(fd == nil)
		return;
	fds := open("/dev/sysname", sys->OWRITE);
	if(fds == nil)
		return;
	buf := array[128] of byte;
	nr := sys->read(fd, buf, len buf);
	if(nr <= 0)
		return;
	sys->write(fds, buf, nr);
}
