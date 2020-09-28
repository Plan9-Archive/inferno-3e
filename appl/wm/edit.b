#
#	Modified version of edit
#	D.B.Knudsen
#
implement WmEdit;

include "sys.m";
	sys: Sys;

include "draw.m";
	draw: Draw;
	Rect, Screen: import draw;

include "tk.m";
	tk: Tk;

include "wmlib.m";
	wmlib: Wmlib;
getstring : import wmlib;

WmEdit: module
{
	init:	fn(ctxt: ref Draw->Context, argv: list of string);
};

ErrIco: con "error -fg red";

ed: ref Tk->Toplevel;
screen: ref Screen;
dirty := 0;

BLUE : con "#0000ff";
GREEN : con "#008800";

SEARCH,
SEARCHFOR,
REPLACE,
REPLACEWITH,
REPLACEALL,
NOSEE : con iota;

ed_config := array[] of {
	"frame .m -relief raised -bd 2",
	"frame .b",
	"menubutton .m.file -text File -menu .m.file.menu",
	"menubutton .m.edit -text Edit -menu .m.edit.menu",
	"menubutton .m.search -text Search -menu .m.search.menu",
	"menubutton .m.options -text Options -menu .m.options.menu",
#	"label .m.filename",
	"pack .m.file .m.edit .m.search .m.options -side left",
#	"pack .m.filename -padx 10 -side left",
	"menu .m.file.menu",
	".m.file.menu add command -label New -command {send c new}",
	".m.file.menu add command -label Open... -command {send c open}",
	".m.file.menu add separator",
	".m.file.menu add command -label Save -command {send c save}",
	".m.file.menu add command -label {Save As...} -command {send c saveas}",
	".m.file.menu add separator",
	".m.file.menu add command -label {Exit} -command {send c exit}",
	"menu .m.edit.menu",
	".m.edit.menu add command -label Cut -command {send c cut}",
	".m.edit.menu add command -label Copy -command {send c copy}",
	".m.edit.menu add command -label Paste -command {send c paste}",
	"bind .m.edit.menu <ButtonRelease> {%W tkMenuButtonUp %x %y}",
	"menu .m.search.menu",
	".m.search.menu add command -label {Find ...} " +
					"-command {send c searchf}",
	".m.search.menu add command -label {Replace with...} " +
					"-command {send c replacew}",
	".m.search.menu add command -label {Find Again} -command {send c search}",
	".m.search.menu add command -label {Find and Replace} " +
					"-command {send c replace}",
	".m.search.menu add command -label {Find and Replace All} " +
					"-command {send c replaceall}",
	"menu .m.options.menu",
	".m.options.menu add checkbutton -text Limbo -command {send c limbo}",
	".m.options.menu add command -label Indent -command {send c indent}",
	"text .b.t  -yscrollcommand {.b.s set} -bg white",
	"bind .b.t <Button-2> {.m.edit.menu post %X %Y}",
	"bind .b.t <Key> +{send c dirtied {%A}}",
	"bind .b.t <ButtonRelease-1> +{send c reindent}",
	"scrollbar .b.s -command {.b.t yview}",
	"pack .m -fill x",
	"pack .b.s -fill y -side left",
	"pack .b.t -fill both -expand 1",
	"pack .b -fill both -expand 1",
	"focus .b.t",
	"pack propagate . 0",
	".b.t tag configure keyword -fg " + BLUE,
	".b.t tag configure comment -fg " + GREEN,
	"update",
};

context : ref Draw->Context;
curfile := "(New)";
snarf := "";
searchfor := "";
replacewith := "";
path := ".";

init(ctxt: ref Draw->Context, argv: list of string)
{
	wmctl: chan of string;

	sys = load Sys Sys->PATH;
	draw = load Draw Draw->PATH;
	tk = load Tk Tk->PATH;
	wmlib = load Wmlib Wmlib->PATH;
	wmlib->init();

	context = ctxt;
	screen = ctxt.screen;

	(ed, wmctl) = wmlib->titlebar(screen, "", "Edit", Wmlib->Appl);

	argv = tl argv;
	if(argv != nil && (hd argv)[0] == '-' ) {
		l := len ed_config;
		for ( i := 0; i < l; i++ ) {
			if ( len ed_config[i] < 10 ||
					ed_config[i][:10] != "text .b.t " )
				continue;
			ed_config[i] = sys->sprint("text .b.t %s " +
					"-yscrollcommand {.b.s set} -bg white",
					hd argv);
			break;
		}
		argv = tl argv;
	}

	c := chan of string;
	tk->namechan(ed, c, "c");
	drag := chan of string;
	tk->namechan(ed, drag, "Wm_drag");
	for (i := 0; i < len ed_config; i++)
		cmd(ed, ed_config[i]);

	(width, height) := defaultsize(ed, screen);
	cmd(ed, ". configure -width " + width + " -height " + height);

	if (argv != nil) {
		e := loadtfile(hd argv);
		if(e != nil)
			wmlib->dialog(ed, ErrIco, "Open file", e, 0, "Ok"::nil);
	}

	wmlib->taskbar(ed, "Edit " + curfile);
	cmd(ed, "update");

	e := cmd(ed, "variable lasterror");
	if(e != "") {
		sys->print("edit error: %s\n", e);
		return;
	}

	cmdloop: for(;;) {
		alt {
		s := <-c =>
			if ( len s > 7 && s[:7] == "dirtied" ) {
				set_dirty(); do_limbo_check(s);
			}
			else
			case s {
			"exit" =>	if ( check_dirty() ){ set_clean(); break cmdloop; }
			"dirtied" =>	set_dirty(); do_limbo_check(s);
			"new" =>	if ( check_dirty()) {set_clean(); do_new();}
			"open" =>	if ( check_dirty() && do_open()) set_clean();
			"save" =>	do_save(0);
			"saveas" =>	do_save(1);
			"cut" =>	do_snarf(1); set_dirty();
			"copy" =>	do_snarf(0);
			"paste" =>	do_paste(); set_dirty();
			"search" =>	do_search(SEARCH);
			"searchf" =>	do_search(SEARCHFOR);
			"replace" =>	do_replace(REPLACE);
			"replacew" =>	do_replace(REPLACEWITH);
			"replaceall" =>	do_replaceall();
			"limbo" =>	do_limbo();
			"indent" =>	do_indent();
			"reindent" =>	re_indent();
			}
			cmd(ed, "focus .b.t");
		s := <-wmctl =>
			if(s == "exit")
				if (check_dirty())
					break cmdloop;
				else
					break;
			task_title: string;
			if (s == "task") {
				if (curfile == "(New)")
					task_title = wmlib->taskbar(ed, "Edit");
				else
					task_title = wmlib->taskbar(ed, "Edit " + curfile);
				cmd(ed, "update");
			}
			wmlib->titlectl(ed, s);
			if (s == "task")
				wmlib->taskbar(ed, task_title);
		s := <-drag =>
			if ( len s < 6 )
				break;
			case s[0:5] {
			    "path=" =>
				if ( check_dirty() == 0 )
					break;
				cmd(ed, "raise .; .b.t delete 1.0 end");
				e = loadtfile(s[5:]);
				if(e != nil)
				    wmlib->dialog(ed, ErrIco, "Open file", e, 0, "Ok"::nil);
			    "font=" =>
				cmd(ed, "raise .; .b.t configure -font " +
									s[5:]);
				cmd(ed, ".b.t configure -width 80w -height 24h");
			}
		}
		cmd(ed, "update");
		e = cmd(ed, "variable lasterror");
		if(e != "") {
			sys->print("edit error: %s\n", e);
			break cmdloop;
		}
	}
}

check_dirty() : int
{
	if ( dirty == 0 )
		return 1;
	if ( wmlib->dialog(ed, ErrIco, "Confirm",
					"File was changed.\nDiscard changes?",
					0, "Yes" :: "No" :: nil) == 0 ) {
		return 1;
	}
	return 0;
}

set_dirty()
{
	if(!dirty){
		dirty = 1;
		wmlib->taskbar(ed, "Edit " + curfile + " (dirty)");
		cmd(ed, "update");
	}
#	We want to just remove the binding, but Inferno's tk does not
#	recognize the - in front of the command.  To make it do so would
#	require changes to utils.c and ebind.c in /tk
#	cmd(ed, "bind .b.t <Key> -{send c dirtied}");
}

set_clean()
{
	if(dirty){
		dirty = 0;
		wmlib->taskbar(ed, "Edit " + curfile);
		cmd(ed, "update");
		#cmd(ed, "bind .b.t <Key> +{send c dirtied}");
	}
}

BLOCK, TEMP : con iota;
is_limbo	:= 0;		# initially not limbo
this_word := "";
last_keyword := "";
in_comment	:= 0;
first_char	:= 1;
indent		: list of int;
last_kw_is_block := 0;
tab		:= "\t";
tabs		:= array[] of {
	"", "\t", "\t\t", "\t\t\t", "\t\t\t\t", "\t\t\t\t\t",
	"\t\t\t\t\t\t", "\t\t\t\t\t\t\t", "\t\t\t\t\t\t\t\t"
};

keywords := array[] of {
	"adt", "alt", "array", "big", "break",
	"byte", "case", "chan", "con", "continue",
	"cyclic", "do", "else", "exit", "fn",
	"for", "hd", "if", "implement", "import",
	"include", "int", "len", "list", "load",
	"module", "nil", "of", "or", "pick",
	"real", "ref", "return", "self", "spawn",
	"string", "tagof", "tl", "to", "type",
	"while"
};
block_keyword := (big 1 << 40 ) | big (1 << 17) | big (1 << 15) |
					big (1 << 12) | big (1 << 11);

do_limbo()
{
	is_limbo = !is_limbo;
	if ( is_limbo )
		mark_keyw_comm();
	else {
		cmd(ed, ".b.t tag remove comment 1.0 end");
		cmd(ed, ".b.t tag remove keyword 1.0 end");
	}
}

do_limbo_check(s : string)
{
	if ( ! is_limbo )
		return;
	if ( len s < 11 )
		return;
#
#   Maybe we should actually remember where the insert point is.
#   In general we can get it via .b.t index insert, but for most
#   characters, we could maintain the position with simple arithmetic.
#
#   Also, we need to insert code in cut and paste operations to keep
#   track of various things when in limbo mode.  Also need to catch
#   text deletions via typeover of selection.
#
	char := s[9];
	if ( char == '\\' && len s > 10 )
		char = s[10];
	case char {
	    ' ' or '\t' =>
		if ( ! in_comment )
			look_keyword(this_word);
		this_word = "" ;
	    '\n' =>
		if ( in_comment ) {
			# terminate current tag
			cmd(ed, ".b.t tag remove comment insert-1chars");
			in_comment = 0;
		}
		else
			look_keyword(this_word);
		this_word = "" ;
		if ( last_kw_is_block )
			indent = TEMP :: indent;
		else while ( indent != nil && hd indent == TEMP )
			indent = tl indent;
		last_kw_is_block = 0;
		add_indent();
		first_char = 1;
		return;
	    '{' =>
		indent = BLOCK :: indent;
		last_kw_is_block = 0;
	    '}' =>
		if ( indent != nil )
			indent = tl indent;
		last_kw_is_block = 0;
	# If the line is just indentation plus '}', rewrite it
	# to have one less indent.
		if ( first_char ) {
			current := int cmd(ed, ".b.t index insert");
			cmd(ed, ".b.t delete " +
						string current + ".0 insert");
			add_indent();
			cmd(ed, ".b.t insert insert '}");
		}
#	    ';' =>
#		last_kw_is_block = 0;
#	    '\b' =>	# By the time we see this, the character has
#			# already been wiped out, probably.
#			# To know what it was we'd need a lastchar,
#			# reset for each mouse button up and \b
#	    '\u007f' =>	# Here, we have to know what used to be ahead of the
#			# insert point.
	    '#' =>
		# if ( ! in_quote ) {
		#	cmd(ed, ".b.t tag add comment insert-1chars");
			in_comment = 1;
		# }
	    'A' to 'Z' or 'a' to 'z' or '0' to '9' or '_' =>
		if ( ! in_comment )
			this_word[len this_word] = char;
	    * =>
		if ( ! in_comment )
			look_keyword(this_word);
		this_word = "";
	}
	if ( in_comment )
		cmd(ed, ".b.t tag add comment insert-1chars");
	first_char = 0;
}

look_keyword(word : string)
{
	# compare this_word to all keywords
	if ( is_keyword(word) ) {
		cmd(ed, ".b.t tag add keyword insert-" +
			string (len this_word + 1) + "chars insert-1chars");
	}
}

is_keyword(word : string) : int
{
	l := len keywords;
	for ( i := 0; i < l; i++ )
		if ( word == keywords[i] ) {
			if ( i != 26 )	# don't set for 'nil'
				last_kw_is_block = int (block_keyword >> i) & 1;
			return 1;
		}
	return 0;
}

do_new()
{
	cmd(ed, ".b.t delete 1.0 end");
	curfile = "(New)";
	wmlib->taskbar(ed, "Edit " + curfile);
}

do_open(): int
{
	for(;;) {
		fname := wmlib->filename(screen, ed, "", nil, path);
		if(fname == "")
			break;
		cmd(ed, ".b.t delete 1.0 end");
		e := loadtfile(fname);
		if(e == nil) {
			basepath(fname);
			return 1;
		}

		options := list of {
			"Cancel",
			"Open another file"
		};

		if(wmlib->dialog(ed, ErrIco, "Open file", e, 0,  options) == 0)
			break;
	}
	return 0;
}

basepath(file: string)
{
	for(i := len file-1; i >= 0; i--)
		if(file[i] == '/') {
			path = file[0:i];
			break;
		}
}

do_save(prompt: int)
{
	fname := curfile;

	contents := cmd(ed, ".b.t get 1.0 end");
	if(len contents > 0 && contents[0] == '!') {
		sys->print("problem getting contents: %s\n", contents);
		return;
	}
	for(;;) {
		if(prompt || curfile == "(New)") {
			fname = getstring(ed, "File");
			if ( len fname > 0 && fname[0] != '/' && path != "" )
				fname = path + "/" + fname;
		}

		if(savetfile(fname, contents)) {
			set_clean();
			break;
		}

		options := list of {
			"Cancel",
			"Try another file"
		};

		msg := sys->sprint("Trying to write file \"%s\"\n%r", fname);
		if(wmlib->dialog(ed, ErrIco, "Save file", msg, 0, options) == 0)
			break;

		prompt = 1;
	}
}

do_snarf(del: int)
{
	range := cmd(ed, ".b.t tag nextrange sel 1.0");
	if(range == "" || (len range > 0 && range[0] == '!'))
		return;
	snarf = cmd(ed, ".b.t get " + range);
	if(del)
		cmd(ed, ".b.t delete " + range);

	if ( (sfd := sys->open("/chan/snarf", Sys->OWRITE)) != nil )
		sys->fprint(sfd, "%s", snarf);
}

do_paste()
{
	if ( (sfd := sys->open("/chan/snarf", Sys->OREAD)) != nil ) {
		buf := array[1024] of byte;
		snarf = "";
		while ( (nbyte := sys->read(sfd, buf, len buf)) > 0 )
			snarf += string buf[0:nbyte];
	}
	if(snarf == "")
		return;
	cmd(ed, ".b.t insert insert '" + snarf);
}

do_search(prompt: int) : int
{
	if(prompt == SEARCHFOR)
		searchfor = getstring(ed, "Search For");
	if(searchfor == "")
		return 0;
	cmd(ed, "cursor -bitmap cursor.wait");
	ix := cmd(ed, ".b.t search -- " + wmlib->tkquote(searchfor) + " insert+1c");
	if(ix != "" && len ix > 1 && ix[0] != '!') {
		cmd(ed, ".b.t tag remove sel 0.0 end");
		cmd(ed, ".b.t mark set anchor " + ix);
		cmd(ed, ".b.t mark set insert " + ix);
		cmd(ed, ".b.t tag add sel " + ix + " " + ix + "+" +
						string(len searchfor) + "c");
		if ( prompt != NOSEE )
			cmd(ed, ".b.t see " + ix);
		cmd(ed, "cursor -default");
		return 1;
	}
	cmd(ed, "cursor -default");
	return 0;
}

do_replace(prompt : int)
{
	range := "";
	if ( prompt == REPLACEWITH ) {
		replacewith = getstring(ed, "Replacement String");

		range = cmd(ed, ".b.t tag nextrange sel 1.0");
		if(range == "" || (len range > 0 && range[0] == '!'))
			return;			# nothing currently selected
	}
	if ( range != "" ) {		# there's something selected
		cmd(ed, ".b.t mark set insert sel.first");
	}
	else {				# have to find a string
		if ( searchfor == "" ) {	# no search string!
			if ( do_search(SEARCHFOR) == 0 )
				return;
		}
		else if ( do_search(SEARCH) == 0 )
			return;
	}
	cmd(ed, ".b.t delete sel.first sel.last");
	cmd(ed, ".b.t insert insert " + wmlib->tkquote(replacewith));
}

do_replaceall()
{
	cur := cmd(ed, ".b.t index insert");
	if ( cur == "" || cur[0] == '!' )
		return;
	dirt := 0;
	if ( searchfor == "" )		# no search string
		searchfor = getstring(ed, "Search For");
	if ( searchfor == "" )		# still no search string
		return;
	srch := wmlib->tkquote(searchfor);
	repl := wmlib->tkquote(replacewith);
	for ( ix := "1.0"; len ix > 0 && ix[0] != '!'; ) {
		ix = cmd(ed, ".b.t search -- " + srch + " " + ix + " end");
		if ( ix == "" || len ix <= 1 || ix[0] == '!')
			break;
		cmd(ed, ".b.t delete " + ix + " " + ix + "+" +
						string(len searchfor) + "c");
		if ( replacewith != "" ) {
			cmd(ed, ".b.t insert " + ix + " " + repl);
			ix = cmd(ed, ".b.t index " + ix + "+" +
					string(len replacewith) + "c");
		}
		dirt++;
	}
	cmd(ed, ".b.t mark set insert " + cur);
	if ( dirt > 0 )
		set_dirty();
}
	

loadtfile(path: string): string
{
	if ( path != nil && path[0] == '/' )
		basepath(path);
	fd := sys->open(path, sys->OREAD);
	if(fd == nil)
		return "Can't open "+path+", the error was:\n"+sys->sprint("%r");
	(ok, d) := sys->fstat(fd);
	if(ok < 0)
		return "Can't stat "+path+", the error was:\n"+sys->sprint("%r");
	if(d.mode & sys->CHDIR)
		return path+" is a directory";

	cmd(ed, "cursor -bitmap cursor.wait");
	BLEN: con 8192;
	buf := array[BLEN+Sys->UTFmax] of byte;
	inset := 0;
	for(;;) {
		n := sys->read(fd, buf[inset:], BLEN);
		if(n <= 0)
			break;
		n += inset;
		nutf := sys->utfbytes(buf, n);
		s := string buf[0:nutf];
		# move any partial rune to beginning of buffer
		inset = n-nutf;
		buf[0:] = buf[nutf:n];
		cmd(ed, ".b.t insert end '" + s);
	}
	if ( is_limbo )
		mark_keyw_comm();
	curfile = path;
	wmlib->taskbar(ed, "Edit " + curfile);
	cmd(ed, "cursor -default");
	cmd(ed, "update");
	return "";
}

savetfile(path: string, contents: string): int
{
	buf := array of byte contents;
	n := len buf;

	fd := sys->create(path, sys->OWRITE, 8r664);
	if(fd == nil)
		return 0;
	i := sys->write(fd, buf, n);
	if(i != n) {
		sys->print("savetfile only wrote %d of %d: %r\n", i, n);
		return 0;
	}
	curfile = path;
#	cmd(ed, ".m.filename configure -text '" + curfile);
	wmlib->taskbar(ed, "Edit " + curfile);

	return 1;
}

mark_keyw_comm()
{
	quote := 0;
	start : int;
	notkey := 0;
	word : string;

	last := int cmd(ed, ".b.t index end");
	for ( i := 1; i <= last; i++ ) {
		quote = 0;
		word = "";
		line := cmd(ed, ".b.t get " + string i + ".0 " +
						string (i+1) + ".0");
		l := len line;
ll :		for ( j := 0; j < l; j++ ) {
			c := line[j];
			if ( quote && (c = line[j]) != quote )
				continue;
			case c {
			    '#' =>
				cmd(ed, sys->sprint(".b.t tag add comment" +
					" %d.%d %d.%d", i, j, i, l));
				break ll;
			    '\'' or '\"' =>
				if ( j != 0 && line[j-1] == '\\' )
					break;
				if ( c == quote )
					quote = 0;
				else
					quote = line[j];
				word = "";
			    'a' to 'z' =>
				if ( word == "" )
					start = j;
				word[len word] = c;
			    'A' to 'Z' or '_' =>
				notkey = 1;
				continue;
			    * =>
				if ( ! notkey && is_keyword(word) )
					cmd(ed, ".b.t tag add keyword " +
						sys->sprint("%d.%d %d.%d",
							i, start, i, j));
				word = "";
				notkey = 0;
			}
		}
	}
}

do_indent()
{
	for ( ; ; ) {
		tab = getstring(ed, "single indent");
		break;
	}
	for ( i := 1; i <= 8; i++ ) {
		s := "";
		for ( j := i; j > 0; j-- )
			s += tab;
		tabs[i] = collapse(s);
	}	
}

collapse(s : string) : string
{
	if ( len s >= 8 && s[0:8] == "        " )
		return "\t" + collapse(s[8:]);
	return s;
}

add_indent()
{
	for ( i := len indent; i >= 8; i -= 8 )
		cmd(ed, ".b.t insert insert '" + tabs[8]);
	cmd(ed, ".b.t insert insert '" + tabs[i]);
}
#
#	We should also look at the previous line, maybe.
#	And the line after.  That may be too much.
#
#	This is also the logical place to check if we are in a keyword,
#	reinitialize this_word (which presents problems if we are in the
#	middle of a word, etc.)  Also check if we are in a comment or not.  
#
re_indent()
{
	pos := cmd(ed, ".b.t index insert");
	(n, lc) := sys->tokenize(pos, ".");
	if ( n < 2 )
		return;
	init := cmd(ed, ".b.t get " + hd lc + ".0 insert");
	l := len init;
	for ( i := 8; i > 0; i-- ) {
		lt := len tabs[i];
		if ( l >= lt && init[:lt] == tabs[i] )
			break;
	}
	for ( indent = nil; len indent < i; indent = 0 :: indent) ;
	
	in_comment = 0;		# Are we in a comment?
	for ( i = len tabs[i]; i < l; i++ )
		if ( init[i] == '#' ) {
			in_comment = 1;
			break;
		}
}

defaultsize(top: ref Tk->Toplevel, screen: ref Draw->Screen): (string, string)
{
	r := screen.image.r;
	(ox, oy) := (int cmd(top, ". cget -actx"), int cmd(top, ". cget -acty"));
	(w, h) := (r.dx(), r.dy());
	if(w > 600 && h > 400){
		(w, h) = (80*w/100, 70*h/100);
		if(ox+w > r.max.x)
			w = r.max.x-ox;
		if(oy+h > r.max.y)
			h = r.max.y-oy;
		if(w > 700)
			w = 80*w/100;
		if(h > 700)
			h = 80*h/100;
	}else
		h -= 20;
	return (string w, string h);
}

cmd(win: ref Tk->Toplevel, s: string): string
{
#	sys->print("%s\n", s);
	r := tk->cmd(win, s);
	if (r != nil && r[0] == '!') {
		sys->print("wm/edit: error executing '%s': %s\n", s, r);
	}
	return r;
}
