#include "lib9.h"
#include <sys/types.h>
#include <sys/stat.h>
#include <pwd.h>
#include <grp.h>

static void
statconv(Dir *dir, struct stat *s)
{
	struct passwd *p;
	struct group *g;
	ulong q;

	p = getpwuid(s->st_uid);
	if (p)
		strncpy(dir->uid, p->pw_name, NAMELEN);
	g = getgrgid(s->st_gid);
	if (g)
		strncpy(dir->gid, g->gr_name, NAMELEN);
	q = 0;
	if(S_ISDIR(s->st_mode))
		q = CHDIR;
	q |= s->st_ino & 0x00FFFFFFUL;
	strncpy(dir->name, "", NAMELEN);
	dir->qid.path = q;
	dir->qid.vers = s->st_mtime;
	dir->mode = (dir->qid.path&CHDIR)|(s->st_mode&0777);
	dir->atime = s->st_atime;
	dir->mtime = s->st_mtime;
	dir->length = s->st_size;
	dir->dev = s->st_dev;
	dir->type = 'M';
	if(S_ISFIFO(s->st_mode))
		dir->type = '|';
}

int
dirfstat(int fd, Dir *d)
{
	struct stat sbuf;

	if(fstat(fd, &sbuf) < 0)
		return -1;
	statconv(d, &sbuf);
	return 0;
}

int
dirstat(char *f, Dir *d)
{
	struct stat sbuf;

	if(stat(f, &sbuf) < 0)
		return -1;
	statconv(d, &sbuf);
	return 0;
}
