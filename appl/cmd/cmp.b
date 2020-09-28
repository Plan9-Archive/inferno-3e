implement Cmp;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;

BUF: con 65536;
stderr: ref Sys->FD;

Cmp: module
{
	init: fn(nil: ref Draw->Context, argv: list of string);
};

init(nil: ref Draw->Context, argv: list of string)
{
	sys = load Sys Sys->PATH;

	f1,f2 : ref Sys->FD;
	lflag := Lflag := sflag := 0;
	n,i,n1,n2: int;
	buf1 := array[BUF] of byte;
	buf2 := array[BUF] of byte;
	nc := 1;
	o : int;
	l := 1;

	stderr = sys->fildes(2);

	argv = tl argv;
	if(argv == nil)
		usage();
	
	name1:= hd argv;
	if (name1[0]=='-') {
		for(i=1;i<len name1;i++){
			case name1[i] {
			'l' =>		lflag = 1;
			'L' =>	Lflag = 1;
			's' =>		sflag = 1;
			* =>		usage();
			}
		}
		argv=tl argv;
		if(argv == nil)
			usage();
		name1=hd argv;
	}	

	if(len argv < 2)
		usage();

	if((f1 = sys->open(name1, Sys->OREAD)) == nil){
		sys->fprint(stderr, "cmp: can't open %s: %r\n",name1);
		sys->raise("fail:open error");
	}
	argv = tl argv;
	name2 := hd argv;

	if((f2 = sys->open(name2, Sys->OREAD)) == nil){
		sys->fprint(stderr, "cmp: can't open %s: %r\n",name2);
		sys->raise("fail:open error");
	}

	argv = tl argv;
	if(argv != nil){
		o = int hd argv;
		if(sys->seek(f1, o, 0) < 0){
			sys->fprint(stderr, "cmp: seek by offset1 failed: %r\n");
			sys->raise("fail:seek error");
		}
		argv = tl argv;
	}

	if(argv != nil){
		o = int hd argv;
		if(sys->seek(f2, o, 0) < 0){
			sys->fprint(stderr, "cmp: seek by offset2 failed: %r");
			sys->raise("fail:seek error");
		}
	}
	if(argv != nil)
		usage();
	b1 := 0;
	b2 := 0;
	diff := 0;
	for(;;){
		n1 = sys->read(f1, buf1, BUF);
		b1 += n1;
		n2 = sys->read(f2, buf2, BUF);
		b2 += n2;
		n = n2;
		if(n > n1)
			n = n1;
		if(n <= 0)
			break;
		for(i=0;i<n;i++){
			if (Lflag && (buf1[i]== byte '\n'))
				l++;
			if (buf1[i]!=buf2[i]){
				if(!lflag) {
					if (!sflag) {
						sys->print("%s %s differ: char %d",
									name1, name2, nc+i);
						if (Lflag==1)
							sys->print(" line %d\n", l);
						else
							sys->print("\n");
					}
					sys->raise("fail:differences");
				}
				sys->print("%6d %.2x %.2x\n", nc+i, int buf1[i], int buf2[i]);
				diff = 1;
			}
		}
		nc += n;
		b1 += n;
		b2 += n;
		if (n1!=n2)
			break;
	}
	if(n1 != n2) {
		if (n1>n2)
			sys->print("EOF on %s\n", name2);
		else 
			sys->print("EOF on %s\n", name1);
		diff = 1;
	}
	if (diff)
		sys->raise("fail:differences");
	exit;
}


usage() 
{
	sys->fprint(stderr, "Usage: cmp [-lL] file1 file2 [offset1 [offset2] ]\n");
	sys->raise("fail:usage");
}
