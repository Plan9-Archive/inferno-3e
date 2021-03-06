# Directories common to all architectures.
# Build in order:
#	- critical libraries used by the limbo compiler
#	- the limbo compiler (used to build some subsequent libraries)
#	- the remaining libraries
#	- commands
#	- utilities

EMUDIRS=\
	lib9\
	libbio\
	crypt\
	math\
	limbo\
	interp\
	keyring\
	image\
	prefab\
	tk\
	memimage\
	memlayer\
	asm\
	kfs\
	emu\

KERNEL_DIRS=\
	os/sa1100\
	os/pc\
	os/mpc\
	os/js\
	os/boot/mpc\
	os/boot/sa1100\

# mkconfig is included at this point to allow it to override
#the preceding declarations (particularly KERNEL_DIRS) if need be

<mkconfig

DIRS=\
	$EMUDIRS\
	appl\

foo:QV:
	echo mk all, clean, install, installall or nuke

all:V:		all-$HOSTMODEL
clean:V:	clean-$HOSTMODEL
install:V:	install-$HOSTMODEL
installall:V:	installall-$HOSTMODEL
emu:V:	emu/all-$HOSTMODEL
emuinstall:V:	emu/install-$HOSTMODEL
emuclean:V:	emu/clean-$HOSTMODEL
emunuke:V:	emu/nuke-$HOSTMODEL
kernel:V:	kernel/all-$HOSTMODEL
kernelall:V:	kernel/all-$HOSTMODEL
kernelclean:V:	kernel/clean-$HOSTMODEL
kernelinstall:V:	kernel/install-$HOSTMODEL
kernelinstallall:V:	kernel/installall-$HOSTMODEL
kernelnuke:V:	kernel/nuke-$HOSTMODEL
# kerneluninstall:V:	kernel/uninstall-$HOSTMODEL
nuke:V:		nuke-$HOSTMODEL
# uninstall:V:	uninstall-$HOSTMODEL

cleandist:V: clean
	rm -f $ROOT/$OBJDIR/lib/lib*.a

nukedist:V: nuke
	rm -f $ROOT/$OBJDIR/bin/*.exe
	rm -f $ROOT/$OBJDIR/lib/lib*.a
	
&-Posix:QV:
	for j in $DIRS libregexp utils tools
	do
		echo "(cd $j; mk $MKFLAGS $stem)"
		(cd $j; mk $MKFLAGS $stem)
	done

&-Nt:QV:
	for (j in $DIRS libregexp utils tools)
	{
		echo '@{builtin cd' $j '; mk $MKFLAGS $stem}'
		@{builtin cd $j; mk.exe $MKFLAGS $stem }
	}

&-Inferno:QV:
	for (j in $DIRS libregexp utils)
	{
		echo '@{builtin cd' $j '; mk $MKFLAGS $stem}'
		@{builtin cd $j; mk $MKFLAGS $stem }
	}

&-Plan9:QV:
	for (j in $DIRS libregexp utils)
	{
		echo '@{builtin cd' $j '; mk $MKFLAGS $stem}'
		@{builtin cd $j; mk $MKFLAGS $stem }
	}

emu/&-Posix:QV:
	for j in $EMUDIRS
	do
		echo "(cd $j; mk $MKFLAGS $stem)"
		(cd $j; mk $MKFLAGS $stem)
	done

emu/&-Nt:QV:
	for (j in $EMUDIRS)
	{
		echo '@{builtin cd' $j '; mk $MKFLAGS $stem}'
		@{builtin cd $j; mk $MKFLAGS $stem }
	}

emu/&-Plan9:QV:
	for (j in $EMUDIRS)
	{
		echo '@{builtin cd' $j '; mk $MKFLAGS $stem}'
		@{builtin cd $j; mk $MKFLAGS $stem }
	}

kernel/&-Posix:QV:
	for j in $KERNEL_DIRS
	do
		echo "(cd $j; mk $MKFLAGS $stem)"
		(cd $j; mk $MKFLAGS $stem)
	done

kernel/&-Nt:QV:
	for (j in $KERNEL_DIRS)
	{
		echo '@{builtin cd' $j '; mk $MKFLAGS $stem}'
		@{builtin cd $j; mk $MKFLAGS $stem }
	}

kernel/&-Inferno:QV:
	for (j in $KERNEL_DIRS)
	{
		echo '@{builtin cd' $j '; mk $MKFLAGS $stem}'
		@{builtin cd $j; mk $MKFLAGS $stem }
	}

kernel/&-Plan9:QV:
	for (j in $KERNEL_DIRS)
	{
		echo '@{builtin cd' $j '; mk $MKFLAGS $stem}'
		@{builtin cd $j; mk $MKFLAGS $stem }
	}

# Convenience targets

Hp-% hp-%:V:
	mk 'SYSHOST=Hp' 'OBJTYPE=s800' $stem

Inferno-% inferno-% Inferno-386-% inferno-386-%:V:
	mk 'SYSHOST=Inferno' 'OBJTYPE=386' $stem

Inferno-arm-% inferno-arm-%:V:
	mk 'SYSHOST=Inferno' 'OBJTYPE=arm' $stem

Plan9-% plan9-%:V:
	mk 'SYSHOST=Plan9' 'OBJTYPE=386' $stem

Irix-% irix-%:V:
	mk 'SYSHOST=Irix' 'OBJTYPE=mips' $stem

Linux-% linux-%:V:
	mk 'SYSHOST=Linux' 'OBJTYPE=386' $stem

NetBSD-% netbsd-%:V:
	mk 'SYSHOST=NetBSD' 'OBJTYPE=386' $stem

Nt-% nt-% Win95-% win95-%:V:
	mk 'SYSHOST=Nt' 'OBJTYPE=386' $stem

Solaris-% solaris-%:V:
	mk 'SYSHOST=Solaris' 'OBJTYPE=sparc' $stem
