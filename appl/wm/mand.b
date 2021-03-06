implement Mand;

#
# Copyright © 2000 Vita Nuova Limited. All rights reserved.
#

# mandelbrot/julia fractal browser:
# button 1 - drag a rectangle to zoom into
# button 2 - (from mandel only) show julia at point
# button 3 - zoom out

include "sys.m";
	sys : Sys;
include "draw.m";
	draw : Draw;
	Point, Rect, Image, Context, Screen, Display : import draw;
include "tk.m";
	tk: Tk;
include "wmlib.m";
	wmlib: Wmlib;

Mand : module
{
	init : fn(nil : ref Context, argv : list of string);
};

colours: array of ref Image;
stderr : ref Sys->FD;

FIX: type big;

Calc: adt {
	xr, yr: array of FIX;
	parx, pary: FIX;
	# column order
	dispbase: array of COL;		# auxiliary display and border
	imgch: chan of (ref Image, Rect);
	img: ref Image;
	maxx, maxy, supx, supy: int;
	disp: int;					# origin of auxiliary display
	morj : int;
	winr: Rect;
	kdivisor: int;
	pointsdone: int;
};

# BASE, LIMIT, MAXCOUNT, MINDELTA may be varied

#
#	calls with 256X128 on initial set
#	---------------------------------
#	crawl		58	(5% of time)
#	fillline	894	(6% of time)
#	isblank		5012	(0% of time)
#	mcount		6928	(55% of time)
#	getcolour	52942	(11% of time)
#	displayset	1	(15% of time)
#
WHITE : con 16r0;
BLACK : con 16rff;

COL : type byte;

BASE	: con 60;		# 28
HBASE : con (BASE/2);
SCALE : con (big 1<<BASE);
TWO	: con (big 1<<(BASE+1));
FOUR : con (big 1<<(BASE+2));
NEG	: con (~((big 1<<(32-HBASE))-big 1));
MINDELTA : con (big 1<<(HBASE-1));		# (1<<(HBASE-2))

SCHEDCOUNT: con 100;

BLANK : con 0;		# blank pixel
BORDER : con 255;	# border pixel
LIMIT : con 4;		# 4 or 5

# pointcolour() returns values in the range 1..MAXCOUNT+1
# these must not clash with 0 or 255
# hence 0 <= MAXCOUNT <= 253
#
MAXCOUNT : con 253;		# 92  64

# colour cube
R, G, B : int;

# initial width and height
WIDTH: con 400;
HEIGHT: con 400;

Fracpoint: adt {
	x, y: real;
};

Fracrect: adt {
	min, max: Fracpoint;
};

Params: adt {
	r: Fracrect;
	p: Fracpoint;
	m: int;
	kdivisor: int;
	fill: int;
};

Usercmd: adt {
	pick {
	Zoomin =>
		r: Rect;
	Julia =>
		p: Point;
	Zoomout or
	Restart =>
		# nothing
	}
};

badmod(mod: string)
{
	sys->fprint(stderr, "mand: cannot load %s: %r\n", mod);
	sys->raise("fail:bad module");
}

win_config := array[] of {
	"frame .f",
	"label .f.dl -text Depth",
	"entry .f.depth",
	".f.depth insert 0 1",
	"checkbutton .f.fill -text {Fill} -command {send cmd fillchanged} -variable fill",
	".f.fill select",
	"pack .f.dl -side left",
	"pack .f.fill -side right",
	"pack .f.depth -side top -fill x",
	"canvas .c -bd 3 -relief sunken -width " + string WIDTH + " -height " + string HEIGHT,
	"image create bitmap saveimage",
	".c create image 0 0 -image saveimage -anchor nw -tags saveimage",
	"pack .f -side top -fill x",
	"pack .c -side bottom -fill both -expand 1",
	"pack propagate . 0",
	"bind .c <Button-1> {send cmd b1 %x %y}",
	"bind .c <ButtonRelease-2> {send cmd b2 %x %y}",
	"bind .c <ButtonRelease-1> {send cmd b1r %x %y}",
	"bind .c <ButtonRelease-3> {send cmd b3 %x %y}",

	"bind .f.depth <Key-\n> {send cmd setkdivisor}",
	"update",
};

init(ctxt: ref Context, argv : list of string)
{
	sys = load Sys Sys->PATH;
	stderr = sys->fildes(2);

	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;

	wmlib = load Wmlib Wmlib->PATH;
	if (wmlib == nil) badmod(Wmlib->PATH);

	if (ctxt == nil) {
		sys->fprint(stderr, "mand: no draw context\n");
		sys->raise("fail:no draw context");
	}
	wmlib->init();
	(win, wmcmd) := wmlib->titlebar(ctxt.screen, "", "Fractals", Wmlib->Appl);
	sys->pctl(Sys->NEWPGRP, nil);

	cmdch := chan of string;
	tk->namechan(win, cmdch, "cmd");
	for (i := 0; i < len win_config; i++)
		cmd(win, win_config[i]);

	fittoscreen(win);
	cmd(win, "update");
	cmd(win, "bind . <Configure> {send cmd resize}");
	R = G = B = 6;
	argv = tl argv;
	if (argv != nil) { (R, argv) = (int hd argv, tl argv); if (R <= 0) R = 1; }
	if (argv != nil) { (G, argv) = (int hd argv, tl argv); if (G <= 0) G = 1; }
	if (argv != nil) { (B, argv) = (int hd argv, tl argv); if (B <= 0) B = 1; }
	colours = array[256] of ref Image;
	for (i = 0; i < len colours; i++)
		# colours[i] = ctxt.display.color(i);
		colours[i] = ctxt.display.rgb(col(i/(G*B), R),
							    col(i/(1*B), G),
							    col(i/(1*1), B));
	specr := Fracrect((-2.0, -1.5), (1.0, 1.5));
	p := Params(
			correctratio(specr, win),
			(0.0, 0.0),
			1,			# m
			1,			# kdivisor
			int cmd(win, "variable fill")
		);
	pid := -1;
	sync := chan of int;
	imgch := chan of (ref Image, Rect);
	canvr := canvposn(win);
	spawn docalculate(sync, p, imgch);
	pid = <-sync;
	send(imgch, win.image, canvr);

	stack: list of (Fracrect, Params);
	for(;;) alt {
	c := <-wmcmd =>
		case c {
		"move" =>
			if (pid != -1)
				movewin(win, imgch, sync);
			else
				movewin(win, nil, nil);
		* =>
			wmlib->titlectl(win, c);
		}
	press := <-cmdch =>
		(n, toks) := sys->tokenize(press, " ");
		ucmd: ref Usercmd = nil;
		case hd toks {
		"start" =>
			ucmd = ref Usercmd.Restart;
		"resize" =>
			r := canvposn(win);
			if (r.dx() != canvr.dx() || r.dy() != canvr.dy()) {
				ucmd = ref Usercmd.Restart;
				canvr = r;
			}
		"b1" or "b2" or "b3" =>
			#cmd(win, "grab set .c");
			fiximage(win);
			ucmd = trackmouse(win, cmdch, hd toks, Point(int hd tl toks, int hd tl tl toks));
			#cmd(win, "grab release .c");
		"fillchanged" =>
			p.fill = int cmd(win, "variable fill");
			ucmd = ref Usercmd.Restart;
		"setkdivisor" =>
			p.kdivisor = int cmd(win, ".f.depth get");
			if (p.kdivisor < 1)
				p.kdivisor = 1;
			ucmd = ref Usercmd.Restart;
		}
		if (ucmd != nil) {
			restart := 0;
			pick u := ucmd {
			Zoomin =>
				sys->print("zoomin to %s\n", r2s(u.r));
				if (u.r.dx() > 0 && u.r.dy() > 0) {
					stack = (specr, p) :: stack;
					specr.min = pt2real(u.r.min, win, p.r);
					specr.max = pt2real(u.r.max, win, p.r);
					(specr.min.y, specr.max.y) = (specr.max.y, specr.min.y);	# canonicalise
					restart = 1;
				}
			Zoomout =>
				if (stack != nil) {
					((specr, p), stack) = (hd stack, tl stack);
					cmd(win, ".f.depth delete 0 end");
					cmd(win, ".f.depth insert 0 " + string p.kdivisor);
					if (p.fill)
						cmd(win, ".f.fill select");
					else
						cmd(win, ".f.fill deselect");
					cmd(win, "update");
					restart = 1;
				}
			Julia =>
				pt := pt2real(u.p, win, p.r);
				if (p.m) {
					stack = (specr, p) :: stack;
					p.p = pt2real(u.p, win, p.r);
					specr = ((-2.0, -1.5), (1.0, 1.5));
					p.m = 0;
					restart = 1;
				}
			Restart =>
				restart = 1;
			}
			if (restart) {
				if (pid != -1)
					kill(pid);
				win.image.flush(Draw->Flushoff);
				p.r = correctratio(specr, win);
				sync = chan of int;
				spawn docalculate(sync, p, imgch);
				pid = <-sync;
				send(imgch, win.image, canvposn(win));
			}
		}
	<-sync =>
		win.image.flush(Draw->Flushon);
		pid = -1;
	}
}

correctratio(r: Fracrect, win: ref Tk->Toplevel): Fracrect
{
	# make sure calculation rectangle is in
	# the same ratio as bitmap (also make sure that
	# calculated area always includes desired area)
	wr := canvposn(win);
	(btall, atall) := (real wr.dy() / real wr.dx(), (r.max.y - r.min.y) / (r.max.x - r.min.x));
	if (btall > atall) {
		# bitmap is taller than area, so expand area vertically
		excess := (r.max.x - r.min.x) * btall - (r.max.y - r.min.y);
		r.min.y -= excess / 2.0;
		r.max.y += excess / 2.0;
	} else {
		# area is taller than bitmap, so expand area horizontally
		excess := (r.max.y - r.min.y) / btall - (r.max.x - r.min.x);
		r.min.x -= excess / 2.0;
		r.max.x += excess / 2.0;
	}
	return r;
}

pt2real(pt: Point, win: ref Tk->Toplevel, r: Fracrect): Fracpoint
{
	wr := canvposn(win);
	return (real (pt.x - wr.min.x) / real wr.dx() * (r.max.x- r.min.x) + r.min.x,
			real (wr.max.y - pt.y) / real wr.dy() * (r.max.y - r.min.y) + r.min.y);
}

pt2s(pt: Point): string
{
	return string pt.x + " " + string pt.y;
}

r2s(r: Rect): string
{
	return pt2s(r.min) + " " + pt2s(r.max);
}

trackmouse(win: ref Tk->Toplevel, cmdch: chan of string, but: string, p: Point): ref Usercmd
{
	case but {
	"b1" =>
		r := Rect(p, p);
		cmd(win, ".c create rectangle " + r2s(r) + " -outline white -width 1 -tags r");
		cmd(win, "update");
		win.image.flush(Draw->Flushnow);
		do {
			but = <-cmdch;
			(nil, toks) := sys->tokenize(but, " ");
			but = hd toks;
			if(but == "b1"){
				(r.max.x, r.max.y) = (int hd tl toks, int hd tl tl toks);
				cmd(win, ".c coords r " + r2s(r.canon()));
				cmd(win, "update");
			}
		} while (but != "b1r");
		r = r.canon().addpt(canvposn(win).min);
		cmd(win, ".c delete r; update");
		return ref Usercmd.Zoomin(r);
	"b2" =>
		return ref Usercmd.Julia(p.add(canvposn(win).min));
	"b3" =>
		return ref Usercmd.Zoomout;
	}
	return nil;
}

send(imgch: chan of (ref Image, Rect), img: ref Image, r: Rect)
{
	imgch <-= (img, r);
}

movewin(win: ref Tk->Toplevel, imgch: chan of (ref Image, Rect), terminated: chan of int)
{
	if (imgch != nil) {
		# halt calculation process
		alt {
		imgch <-= (nil, ((0,0), (0,0))) =>;
		<-terminated =>
			imgch = nil;
		}
	}
	fiximage(win);
	wmlib->titlectl(win, "move");
	nr := canvposn(win);
	if (imgch != nil)
		imgch <-= (win.image, nr);		# start it again
}

# "fix" the image that we've drawn on the window so it's a
# genuine part of the canvas.
fiximage(win: ref Tk->Toplevel)
{
	r := canvposn(win);
	displ := win.image.display;
	# XXX compensate for bug in canvas widget
	cmd(win, ".c configure -width [.c cget -actwidth]");
	cmd(win, ".c configure -height [.c cget -actheight]");
	saveimage := displ.newimage(r, displ.image.ldepth, 0, Draw->White);
	saveimage.draw(r, win.image, displ.ones, r.min);
	tk->imageput(win, "saveimage", saveimage, nil);
	cmd(win, ".c coords saveimage 0 0");
	cmd(win, "update");
}

poll(calc: ref Calc)
{
	calc.img.flush(Draw->Flushnow);
	alt {
	<-calc.imgch =>
		calc.img = nil;
		(calc.img, calc.winr) = <-calc.imgch;
	* =>;
	}
}

docalculate(sync: chan of int, p: Params, imgch: chan of (ref Image, Rect))
{
	r := p.r;
	if (p.m)
		sys->print("mandel [[%g,%g],[%g,%g]]\n", r.min.x, r.min.y, r.max.x, r.max.y);
	else
		sys->print("julia  [[%g,%g],[%g,%g]] [%g,%g]\n",
			r.min.x, r.min.y, r.max.x, r.max.y, p.p.x, p.p.y);
	sync <-= sys->pctl(0, nil);
	calculate(p, imgch);
	sync <-= 0;
}

canvposn(win: ref Tk->Toplevel): Rect
{
	r: Rect;
	r.min.x = int cmd(win, ".c cget -actx") + int cmd(win, ".c cget -bd");
	r.min.y = int cmd(win, ".c cget -acty") + int cmd(win, ".c cget -bd");
	r.max.x = r.min.x + int cmd(win, ".c cget -actwidth");
	r.max.y = r.min.y + int cmd(win, ".c cget -actheight");
	return r;
}

calculate(p: Params, imgch: chan of (ref Image, Rect))
{
	calc := ref Calc;
	{t := <-imgch; (calc.img, calc.winr) = t; t.t0 =nil;}
	r := calc.winr;
	calc.maxx = r.dx();
	calc.maxy = r.dy();
	calc.supx = calc.maxx + 2;
	calc.supy = calc.maxy + 2;
	calc.imgch = imgch;
	calc.xr = array[calc.maxx] of FIX;
	calc.yr = array[calc.maxy] of FIX;
	calc.morj = p.m;
	initr(calc, p);
	calc.img.draw(r, calc.img.display.zeros, nil, (0,0));

	if (p.fill) {
		calc.dispbase = array[calc.supx*calc.supy] of COL;		# auxiliary display and border
		calc.disp = calc.maxy + 3;
		setdisp(calc);
		displayset(calc);
	} else {
		for (x := 0; x < calc.maxx; x++) {
			for (y := 0; y < calc.maxy; y++)
				point(calc, calc.img, (x, y), pointcolour(calc, x, y));
		}
	}
}
 
setdisp(calc: ref Calc)
{
	d : int;
	i : int;

	for (i = 0; i < calc.supx*calc.supy; i++)
		calc.dispbase[i] = byte BLANK;

	i = 0;
	for (d = 0; i < calc.supx; d += calc.supy) {
		calc.dispbase[d] = byte BORDER;
		i++;
	}
	i = 0;
	for (d = 0; i < calc.supy; d++) {
		calc.dispbase[d] = byte BORDER;
		i++;
	}
	i = 0;
	for (d = 0+calc.supx*calc.supy-1; i < calc.supx; d -= calc.supy) {
		calc.dispbase[d] = byte BORDER;
		i++;
	}
	i = 0;
	for (d = 0+calc.supx*calc.supy-1; i < calc.supy; d--) {
		calc.dispbase[d] = byte BORDER;
		i++;
	}
}

initr(calc: ref Calc, p: Params): int
{
	r := p.r;
	dp := real2fix((r.max.x-r.min.x)/(real calc.maxx));
	dq := real2fix((r.max.y-r.min.y)/(real calc.maxy));
	calc.xr[0] = real2fix(r.min.x)-(big calc.maxx*dp-(real2fix(r.max.x)-real2fix(r.min.x)))/big 2;
	for (x := 1; x < calc.maxx; x++)
		calc.xr[x] = calc.xr[x-1] + dp;
	calc.yr[0] = real2fix(r.max.y)+(big calc.maxy*dq-(real2fix(r.max.y)-real2fix(r.min.y)))/big 2;
	for (y := 1; y < calc.maxy; y++)
		calc.yr[y] = calc.yr[y-1] - dq;
	calc.parx = real2fix(p.p.x);
	calc.pary = real2fix(p.p.y);
	calc.kdivisor = p.kdivisor;
	calc.pointsdone = 0;
	return dp >= MINDELTA && dq >= MINDELTA;
}

fillline(calc: ref Calc, x, y, d, dir, dird, col: int)
{
	x0 := x;

	while (calc.dispbase[d] == byte BLANK) {
		calc.dispbase[d] = byte col;
		x -= dir;
		d -= dird;
	}
	if (0 && pointcolour(calc, (x0+x+dir)/2, y) != col) {		# midpoint of line (island code)
		# island - undo colouring or do properly
		do {
			d += dird;
			x += dir;
			# *d = BLANK;
			calc.dispbase[d] = byte pointcolour(calc, x, y);
			point(calc, calc.img, (x, y), int calc.dispbase[d]);
		} while (x != x0);
		return;				# abort crawl ?
	}
	horizline(calc, calc.img, x0, x, y, col);
}
 
crawlt(calc: ref Calc, x, y, d, col: int)
{
	yinc, dyinc : int;
 
	firstd := d;
	xinc := 1;
	dxinc := calc.supy;
 
	for (;;) {
		if (getcolour(calc, x+xinc, y, d+dxinc) == col) {
			x += xinc;
			d += dxinc;
			yinc = -xinc;
			dyinc = -dxinc;
			# if (isblank(x+xinc, y, d+dxinc))
			if (calc.dispbase[d+dxinc] == byte BLANK)
				fillline(calc, x+xinc, y, d+dxinc, yinc, dyinc, col);
			if (d == firstd)
				break;
		}
		else { 
			yinc = xinc;
			dyinc = dxinc;
		}
		if (getcolour(calc, x, y+yinc, d+yinc) == col) {
			y += yinc;
			d += yinc;
			xinc = yinc;
			dxinc = dyinc;
			# if (isblank(x-xinc, y, d-dxinc))
			if (calc.dispbase[d-dxinc] == byte BLANK)
				fillline(calc, x-xinc, y, d-dxinc, yinc, dyinc, col);
			if (d == firstd)
				break;
		}
		else { 
			xinc = -yinc;
			dxinc = -dyinc;
		}
	}
}

# spurious lines problem - disallow all acw paths
#
#	43--------->
#	12--------->
#
#	654------------>
#	7 3------------>
#	812------------>
#

# Given a closed curve completely described by unit movements LRUD (left,
# right, up, and down), calculate the enclosed area.  The description
# may be cw or acw and of arbitrary shape.
#
# Based on Green's Theorem :-  area = integral  ydx
#					    C
# area = 0;
# count = ARBITRARY_VALUE;
# while( moves_are_left() ){
#     move = next_move();
#    switch(move){
#        case L:
#            area -= count;
#            break;
#        case R:
#            area += count;
#            break;
#        case U:
#            count++;
#            break;
#        case D:
#            count--;
#            break;
#    }
#    area = abs(area);

crawlf(calc: ref Calc, x, y, d, col: int)
{
	xinc, yinc, dxinc, dyinc : int;
	firstx, firsty : int;
	firstd : int;
	area := 0;
	count := 0;
 
	firstx = x;
	firsty = y;
	firstd = d;
	xinc = 1;
	dxinc = calc.supy;
 
	# acw on success, cw on failure
	for (;;) {
		if (getcolour(calc, x+xinc, y, d+dxinc) == col) {
			x += xinc;
			d += dxinc;
			yinc = -xinc;
			dyinc = -dxinc;
			area += xinc*count;
			if (d == firstd)
				break;
		} else { 
			yinc = xinc;
			dyinc = dxinc;
		}
		if (getcolour(calc, x, y+yinc, d+yinc) == col) {
			y += yinc;
			d += yinc;
			xinc = yinc;
			dxinc = dyinc;
			count -= yinc;
			if (d == firstd)
				break;
		} else { 
			xinc = -yinc;
			dxinc = -dyinc;
		}
	}
	if (area > 0)	# cw
		crawlt(calc, firstx, firsty, firstd, col);
}

displayset(calc: ref Calc)
{
	edge : int;
	last := BLANK;
	d := calc.disp;
 
	for (x := 0; x < calc.maxx; x++) {
		for (y := 0; y < calc.maxy; y++) {
			col := calc.dispbase[d];
			if (col == byte BLANK) {
				col = calc.dispbase[d] = byte pointcolour(calc, x, y);
				point(calc, calc.img, (x, y), int col);
				if (col == byte last)
					edge++;
				else {
					last = int col;
					edge = 0;
				}
				if (edge >= LIMIT) {
					crawlf(calc, x, y-edge, d-edge, last);
					# prevent further crawlf()
					last = BLANK;
				}
			}
			else {
				if (col == byte last)
					edge++;
				else {
					last = int col;
					edge = 0;
				}
			}
			d++;
		}
		last = BLANK;
		d += 2;
	}
}

pointcolour(calc: ref Calc, x, y: int) : int
{
	if (++calc.pointsdone >= SCHEDCOUNT) {
		calc.pointsdone = 0;
		sys->sleep(0);
		poll(calc);
	}
	if (calc.morj)
		return mcount(calc, x, y) + 1;
	else
		return jcount(calc, x, y) + 1;
}

mcount(calc: ref Calc, x_coord, y_coord: int): int
{
	(p, q) := (calc.xr[x_coord], calc.yr[y_coord]);
	(x, y) := (calc.parx, calc.pary);
	k := 0;
	maxcount := MAXCOUNT * calc.kdivisor;
	while (k < maxcount) {
		if (x >= TWO || y >= TWO || x <= -TWO || y <= -TWO)
			break;

		if (0) {
			# x = (x < 0) ? (x>>HBASE)|NEG : x>>HBASE;
			# y = (y < 0) ? (y>>HBASE)|NEG : y>>HBASE;
		}

		x >>= HBASE;
		y >>= HBASE;
		t := y*y;
		y = big 2*x*y+q;	# possible unserious overflow when BASE == 28
		x *= x;
		if (x+t >= FOUR) 
			break;
		x -= t-p;
		k++;
	}
	return k / calc.kdivisor;
}

jcount(calc: ref Calc, x_coord, y_coord: int): int
{
	(x, y) := (calc.xr[x_coord], calc.yr[y_coord]);
	(p, q) := (calc.parx, calc.pary);
	k := 0;
	maxcount := MAXCOUNT * calc.kdivisor;
	while (k < maxcount) {
		if (x >= TWO || y >= TWO || x <= -TWO || y <= -TWO)
			break;

		if (0) {
			# x = (x < 0) ? (x>>HBASE)|NEG : x>>HBASE;
			# y = (y < 0) ? (y>>HBASE)|NEG : y>>HBASE;
		}

		x >>= HBASE;
		y >>= HBASE;
		t := y*y;
		y = big 2*x*y+q;	# possible unserious overflow when BASE == 28
		x *= x;
		if (x+t >= FOUR) 
			break;
		x -= t-p;
		k++;
	}
	return k / calc.kdivisor;
}

getcolour(calc: ref Calc, x, y, d: int): int
{
	if (calc.dispbase[d] == byte BLANK) {
		calc.dispbase[d] = byte pointcolour(calc, x, y);
		point(calc, calc.img, (x, y), int calc.dispbase[d]);
	}
	return int calc.dispbase[d];
}

point(calc: ref Calc, d: ref Image, p: Point, col: int)
{
	d.draw(Rect(p, p.add((1,1))).addpt(calc.winr.min), colours[col], nil, (0,0));
}

horizline(calc: ref Calc, d: ref Image, x0, x1, y: int, col: int)
{
	if (x0 < x1)
		r := Rect((x0, y), (x1, y+1));
	else
		r = Rect((x1+1, y), (x0+1, y+1));
	d.draw(r.addpt(calc.winr.min), colours[col], nil, (0, 0));
	# r := Rect((x0, y), (x1, y)).canon();
	# r.max = r.max.add((1, 1));
}

real2fix(x: real): FIX
{
	return big (x * real SCALE);
}

cmd(top: ref Tk->Toplevel, s: string): string
{
	e := tk->cmd(top, s);
	if (e != nil && e[0] == '!')
		sys->fprint(stderr, "mand: tk error on '%s': %s\n", s, e);
	return e;
}

kill(pid: int): int
{
	fd := sys->open("/prog/"+string pid+"/ctl", Sys->OWRITE);
	if (fd == nil)
		return -1;
	if (sys->write(fd, array of byte "kill", 4) != 4)
		return -1;
	return 0;
}

col(i, r : int) : int
{
	if (r == 1)
		return 0;
	return (255*(i%r))/(r-1);
}

fittoscreen(win: ref Tk->Toplevel)
{
	Point: import draw;
	if (win.image == nil || win.image.screen == nil)
		return;
	r := win.image.screen.image.r;
	scrsize := Point((r.max.x - r.min.x), (r.max.y - r.min.y));
	bd := int cmd(win, ". cget -bd");
	winsize := Point(int cmd(win, ". cget -actwidth") + bd * 2, int cmd(win, ". cget -actheight") + bd * 2);
	if (winsize.x > scrsize.x)
		cmd(win, ". configure -width " + string (scrsize.x - bd * 2));
	if (winsize.y > scrsize.y)
		cmd(win, ". configure -height " + string (scrsize.y - bd * 2));
	actr: Rect;
	actr.min = Point(int cmd(win, ". cget -actx"), int cmd(win, ". cget -acty"));
	actr.max = actr.min.add((int cmd(win, ". cget -actwidth") + bd*2,
				int cmd(win, ". cget -actheight") + bd*2));
	(dx, dy) := (actr.dx(), actr.dy());
	if (actr.max.x > r.max.x)
		(actr.min.x, actr.max.x) = (r.max.x - dx, r.max.x);
	if (actr.max.y > r.max.y)
		(actr.min.y, actr.max.y) = (r.max.y - dy, r.max.y);
	if (actr.min.x < r.min.x)
		(actr.min.x, actr.max.x) = (r.min.x, r.min.x + dx);
	if (actr.min.y < r.min.y)
		(actr.min.y, actr.max.y) = (r.min.y, r.min.y + dy);
	cmd(win, ". configure -x " + string actr.min.x + " -y " + string actr.min.y);
}
