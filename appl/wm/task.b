implement WmTask;

include "sys.m";
	sys: Sys;
	Dir: import sys;

include "draw.m";
	draw: Draw;

include "tk.m";
	tk: Tk;
	Toplevel: import tk;

include	"wmlib.m";
	wmlib: Wmlib;

Prog: adt
{
	pid:	int;
	pgrp: int;
	size:	int;
	state:	string;
	mod:	string;
};

WmTask: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

Wm: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

task_cfg := array[] of {
	"frame .fl",
	"scrollbar .fl.scroll -command {.fl.l yview}",
	"listbox .fl.l -width 40w -yscrollcommand {.fl.scroll set}",
	"frame .b",
	"button .b.ref -text Refresh -command {send cmd r}",
	"button .b.deb -text Debug -command {send cmd d}",
	"button .b.files -text Files -command {send cmd f}",
	"button .b.kill -text Kill -command {send cmd k}",
	"button .b.killg -text {Kill Group} -command {send cmd kg}",
	"pack .b.ref .b.deb .b.files .b.kill .b.killg -side left -padx 2 -pady 2",
	"pack .b -fill x",
	"pack .fl.scroll -side left -fill y",
	"pack .fl.l -fill both -expand 1",
	"pack .fl -fill both -expand 1",
	"pack propagate . 0",
};

init(ctxt: ref Draw->Context, nil: list of string)
{
	sys  = load Sys  Sys->PATH;
	draw = load Draw Draw->PATH;
	tk   = load Tk   Tk->PATH;
	wmlib= load Wmlib Wmlib->PATH;

	wmlib->init();

	sysnam := sysname();

	(t, menubut) := wmlib->titlebar(ctxt.screen, "", sysnam, Wmlib->Appl);
	if(t == nil)
		return;

	cmd := chan of string;
	tk->namechan(t, cmd, "cmd");

	wmlib->tkcmds(t, task_cfg);

	readprog(t);

	tk->cmd(t, ".fl.l see end;update");

	for(;;) alt {
	menu := <-menubut =>
		case menu {
		"exit" =>
			return;
		"task" =>
			wmlib->titlectl(t, menu);
			tk->cmd(t, ".fl.l delete 0 end");
			readprog(t);
			tk->cmd(t, ".fl.l see end;update");
		* =>
			wmlib->titlectl(t, menu);
		}
	bcmd := <-cmd =>
		case bcmd {
		"d" =>
			sel := tk->cmd(t, ".fl.l curselection");
			if(sel == "")
				break;
			pid := int tk->cmd(t, ".fl.l get "+sel);
			stk := load Wm "/dis/wm/deb.dis";
			if(stk == nil)
				break;
			spawn stk->init(ctxt, "wm/deb" :: "-p "+string pid :: nil);
			stk = nil;
		"k" or "kg" =>
			sel := tk->cmd(t, ".fl.l curselection");
			if(sel == "")
				break;
			pid := int tk->cmd(t, ".fl.l get "+sel);
			what := "opening ctl file";
			cfile := "/prog/"+string pid+"/ctl";
			cfd := sys->open(cfile, sys->OWRITE);
			if(cfd != nil) {
				if(bcmd == "kg"){
					if(sys->fprint(cfd, "killgrp") > 0){
						cfd = nil;
						refresh(t);
						break;
					}
				}else if(sys->fprint(cfd, "kill") > 0){
					tk->cmd(t, ".fl.l delete "+sel);
					cfd = nil;
					break;
				}
				cfd = nil;
				what = "sending kill request";
			}
			if(bcmd == "k" && sys->sprint("%r") == "file does not exist") {
				refresh(t);
				break;
			}
			wmlib->dialog(t, "error -fg red", "Kill",
					"Error "+what+"\n"+
					 "System: "+sys->sprint("%r"),
					0, "OK" :: nil);
		"r" =>
			refresh(t);
		"f" =>
			sel := tk->cmd(t, ".fl.l curselection");
			if(sel == "")
				break;
			pid := int tk->cmd(t, ".fl.l get "+sel);
			fi := load Wm "/dis/wm/edit.dis";
			if(fi == nil)
				break;
			spawn fi->init(ctxt,
				"edit" ::
				"/prog/"+string pid+"/fd" :: nil);
			fi = nil;
		}
	}
}

refresh(t: ref Tk->Toplevel)
{
	tk->cmd(t, ".fl.l delete 0 end");
	readprog(t);
	tk->cmd(t, ".fl.l see end;update");
}

mkprog(file: string): ref Prog
{
	fd := sys->open("/prog/"+file+"/status", sys->OREAD);
	if(fd == nil)
		return nil;

	buf := array[256] of byte;
	n := sys->read(fd, buf, len buf);
	if(n <= 0)
		return nil;

	(v, l) := sys->tokenize(string buf[0:n], " ");
	if(v < 6)
		return nil;

	prg := ref Prog;
	prg.pid = int hd l;
	l = tl l;
	prg.pgrp = int hd l;
	l = tl l;
	l = tl l;
	# eat blanks in user name
	while(len l > 3)
		l = tl l;
	prg.state = hd l;
	l = tl l;
	prg.size = int hd l;
	l = tl l;
	prg.mod = hd l;

	return prg;
}

readprog(t: ref Toplevel): array of ref Prog
{
	n: int;
	d := array[100] of Dir;

	fd := sys->open("/prog", sys->OREAD);
	if(fd == nil)
		return nil;

	prog := array[100] of ref Prog;
	for(;;) {
		n = sys->dirread(fd, d);
		if(n <= 0)
			break;
		v := 0;
		for(i := 0; i < n; i++) {
			p := mkprog(d[i].name);
			if(p != nil){
				prog[v++] = p;
				l := sys->sprint("%4d %4d %3dK %-7s  %s", p.pid, p.pgrp, p.size, p.state, p.mod);
				tk->cmd(t, ".fl.l insert end '"+l);
			}
		}
	}
	return prog;
}

sysname(): string
{
	fd := sys->open("#c/sysname", sys->OREAD);
	if(fd == nil)
		return "Anon";
	buf := array[128] of byte;
	n := sys->read(fd, buf, len buf);
	if(n < 0) 
		return "Anon";
	return string buf[0:n];
}
