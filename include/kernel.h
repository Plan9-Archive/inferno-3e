extern	int	libread(int, void*, int);
extern	int	libreadn(int, void*, int);
extern	int	libwrite(int, void*, int);
extern	int	libopen(char*, int);
extern	int	libclose(int);
extern	int	libdirfstat(int, Dir*);
extern	int	libbind(char*, char*, int);
extern	void*	libqlalloc(void);
extern	void	libqlfree(void*);
extern	void	libqlock(void*);
extern	void	libqunlock(void*);
extern	void*	libqlowner(void*);
extern	void*	libfdtochan(int, int);
extern	void	libchanclose(void*);
extern	int	kbind(char*, char*, int);
extern	int	kchdir(char*);
extern	int	kclose(int);
extern	int	kcreate(char*, int, ulong);
extern	int	kdirfstat(int, Dir*);
extern	int	kdirfwstat(int, Dir*);
extern	long	kdirread(int, Dir*, long);
extern	int	kdirstat(char*, Dir*);
extern	int	kdirwstat(char*, Dir*);
extern	int	kdup(int, int);
extern	int	kfauth(int, char*);
extern	char*	kfd2path(int);
extern	int	kfstat(int, char*);
extern	int	kfversion(int, int, char*, int);
extern	int	kfwstat(int, char*);
extern	int	kmount(int, char*, int, char*);
extern	int	kopen(char*, int);
extern	int	kpipe(int[2]);
extern	long	kpread(int, void*, long, vlong);
extern	long	kread(int, void*, long);
extern	int	kremove(char*);
extern	long	kseek(int, long, int);
extern	int	kstat(char*, char*);
extern	int	kunmount(char*, char*);
extern	long	kpwrite(int, void*, long, vlong);
extern	long	kwrite(int, void*, long);
extern	int	kwstat(char*, char*);
extern	int	klisten(char*, char*);
extern	int	kannounce(char*, char*);
extern	int	kdial(char*, char*, char*, int*);
extern	void	kerrstr(char*);
extern	void	kwerrstr(char *, ...);
extern	void	kgerrstr(char*);
extern	long	kchanio(void*, void*, int, int);
