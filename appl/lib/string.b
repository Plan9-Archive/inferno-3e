implement String;
include "string.m";

splitl(s: string, cl: string): (string, string)
{
	n := len s;
	for(j := 0; j < n; j++) {
		if(in(s[j], cl))
			return (s[0:j], s[j:n]);
	}
	return (s,"");
}

splitr(s: string, cl: string): (string, string)
{
	n := len s;
	for(j := n-1; j >= 0; j--) {
		if(in(s[j], cl))
			return (s[0:j+1], s[j+1:n]);
	}
	return ("",s);
}

drop(s: string, cl: string): string
{
	n := len s;
	for(j := 0; j < n; j++) {
		if(!in(s[j], cl))
			return (s[j:n]);
	}
	return "";
}

take(s: string, cl: string): string
{
	n := len s;
	for(j := 0; j < n; j++) {
		if(!in(s[j], cl))
			return (s[0:j]);
	}
	return s;
}

in(c: int, s: string): int
{
	n := len s;
	if(n == 0)
		return 0;
	ans := 0;
	negate := 0;
	if(s[0] == '^') {
		negate = 1;
		s = s[1:];
		n--;
	}
	for(i := 0; i < n; i++) {
		if(s[i] == '-' && i > 0 && i < n-1)  {
			if(c >= s[i-1] && c <= s[i+1]) {
				ans = 1;
				break;
			}
			i++;
		}
		else
		if(c == s[i]) {
			ans = 1;
			break;
		}
	}
	if(negate)
		ans = !ans;
	return ans;
}

splitstrl(s: string, t: string): (string, string)
{
	n := len s;
	nt := len t;
	if(nt == 0)
		return ("", s);
	c0 := t[0];
    mainloop:
	for(j := 0; j <= n-nt; j++) {
		if(s[j] == c0) {
			for(k := 1; k < nt; k++)
				if(s[j+k] != t[k])
					continue mainloop;
			return(s[0:j], s[j:n]);
		}
	}
	return (s,"");
}

splitstrr(s: string, t: string): (string, string)
{
	n := len s;
	nt := len t;
	if(nt == 0)
		return (s, "");
	c0 := t[0];
    mainloop:
	for(j := n-nt; j >= 0; j--) {
		if(s[j] == c0) {
			for(k := 1; k < nt; k++)
				if(s[j+k] != t[k])
					continue mainloop;
			return(s[0:j+nt], s[j+nt:n]);
		}
	}
	return ("",s);
}

prefix(pre: string, s: string): int
{
	ns := len s;
	n := len pre;
	if(ns < n)
		return 0;
	for(k := 0; k < n; k++) {
		if(pre[k] != s[k])
			return 0;
	}
	return 1;
}

tolower(s: string): string
{
	r := s;
	for(i := 0; i < len r; i++) {
		c := r[i];
		if(c >= int 'A' && c <= int 'Z')
			r[i] = r[i] + (int 'a' - int 'A');
	}
	return r;
}

toupper(s: string): string
{
	r := s;
	for(i := 0; i < len r; i++) {
		c := r[i];
		if(c >= int 'a' && c <= int 'z')
			r[i] = r[i] - (int 'a' - int 'A');
	}
	return r;
}

toint(s: string, base: int): (int, string)
{
	if(base < 0 || base > 36)
		return (0, s);

	c := 0;
	for(i := 0; i < len s; i++) {
		c = s[i];
		if(c != ' ' && c != '\t' && c != '\n')
			break;
	}

	neg := 0;
	if(c == '+' || c == '-') {
		if(c == '-')
			neg = 1;
		i++;
	}

	ok := 0;
	n := 0;
	for(; i < len s; i++) {
		c = s[i];
		v := base;
		case c {
		'a' to 'z' =>
			v = c - 'a' + 10;
		'A' to 'Z' =>
			v = c - 'A' + 10;
		'0' to '9' =>
			v = c - '0';
		}
		if(v >= base)
			break;
		ok = 1;
		n = n * base + v;
	}

	if(!ok)
		return (0, s);
	if(neg)
		n = -n;
	return (n, s[i:]);
}

append(s: string, l: list of string): list of string
{
	t:	list of string;

	# Reverse l, prepend s, and reverse result.
	while (l != nil) {
		t = hd l :: t;
		l = tl l;
	}
	t = s :: t;
	do {
		l = hd t :: l;
		t = tl t;
	} while (t != nil);
	return l;
}

quoted(argv: list of string): string
{
	return quotedc(argv, nil);
}

quotedc(argv: list of string, cl: string): string
{
	s := "";
	while (argv != nil) {
		arg := hd argv;
		for (i := 0; i < len arg; i++) {
			c := arg[i];
			if (c == ' ' || c == '\t' || c == '\n' || c == '\'' || in(c, cl))
				break;
		}
		if (i < len arg || arg == nil) {
			s += "'" + arg[0:i];
			for (; i < len arg; i++) {
				if (arg[i] == '\'')
					s[len s] = '\'';
				s[len s] = arg[i];
			}
			s[len s] = '\'';
		} else
			s += arg;
		if (tl argv != nil)
			s[len s] = ' ';
		argv = tl argv;
	}
	return s;
}

unquoted(args: string): list of string
{
	OUTWORD, INWORD, INQUOTE, SEENQUOTE: con iota;
	argv: list of string;
	word: string;
	mark := -1;
	state := OUTWORD;
	for (i := len args - 1; i >= 0; i--) {
		c := args[i];
		# if statements are much faster than case statements in compiled mode.
		if (state == INWORD) {
			if (c == '\'') {
				argv = args[i + 1:mark] :: argv;
				mark = i;
				word = nil;
				state = INQUOTE;
			} else if (c == ' ' || c == '\t' || c == '\n') {
				argv = args[i + 1:mark] :: argv;
				state = OUTWORD;
			}
		} else if (state == INQUOTE) {
			if (c == '\'') {
				word = args[i + 1:mark] + word;
				state = SEENQUOTE;
			}
		} else if (state == SEENQUOTE) {
			if (c == ' ' || c == '\t' || c == '\n') {
				argv = word :: argv;
				state = OUTWORD;
			} else if (c == '\'') {
				mark = i + 1;
				state = INQUOTE;
			} else {
				argv = word :: argv;
				mark = i + 1;
				state = INWORD;
			}
		} else {		# OUTWORD
			if (c == '\'') {
				word = nil;
				mark = i;
				state = INQUOTE;
			} else if (c != ' ' && c != '\t'&& c != '\n') {
				mark = i + 1;
				state = INWORD;
			}
		}
	}
	if (state == INWORD)
		argv = args[0:mark] :: argv;
	else if (state == INQUOTE)
		argv = nil;		# unbalanced; nil is better than confused quoted text.
	else if (state == SEENQUOTE)
		argv = word :: argv;
	return argv;
}

# original version, somewhat slower.
#
#unquoted(args: string): list of string
#{
#	argv: list of string;	
#	quote := 0;
#	arg := "";
#	nullarg := 1;
#	for (i := 0; i < len args; i++) {
#		c := args[i];
#		if (quote && c == '\'' && i < len args - 1 && args[i+1] == '\'') {
#			arg[len arg] = c;
#			i++;
#		} else if (c == '\'') {
#			quote = !quote;
#			nullarg = 0;
#		} else if (quote || (c != ' ' && c != '\t' && c != '\n')) {
#			arg[len arg] = c;
#		} else {
#			if (arg != nil || !nullarg) {
#				argv = arg :: argv;
#				arg = nil;
#				nullarg = 1;
#			}
#		}
#	}
#	if (arg != nil || !nullarg)
#		argv = arg :: argv;
#	r: list of string;
#	for (; argv != nil; argv = tl argv)
#		r = hd argv :: r;
#	return r;
#}
