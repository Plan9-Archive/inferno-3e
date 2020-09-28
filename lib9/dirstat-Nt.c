#include "lib9.h"
#include <sys/types.h>
#include <sys/stat.h>

#define ISTYPE(s, t)	(((s)->st_mode&S_IFMT) == t)

static void
statconv(Dir *dir, struct stat *s)
{
	ulong q;

#ifdef NO
	extern char* GetNameFromID(int);

	strncpy(dir->uid, GetNameFromID(s->st_uid), NAMELEN);
	strncpy(dir->gid, GetNameFromID(s->st_gid), NAMELEN);
	p = getpwuid(s->st_uid);
	if (p)
		strncpy(dir->uid, p->pw_name, NAMELEN);
	g = getgrgid(s->st_gid);
	if (g)
		strncpy(dir->gid, g->gr_name, NAMELEN);
#else
	strcpy(dir->uid, "unknown");
	strcpy(dir->gid, "unknown");
#endif
	q = 0;
	if(ISTYPE(s, _S_IFDIR))
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
	if(ISTYPE(s, _S_IFIFO))
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
