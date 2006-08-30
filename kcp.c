
/* Cheap program to make a variable directory first before copying contents.
 * Main use is for kdump because nash does not support variables, hence a 
 * command sequence like the following does not work:
 * date=`date ...`
 * mkdir -p /x/y/$date
 * cp foo /x/y/$date/bar
 *
 * Don Zickus (dzickus@redhat.com)
 *
 * Copyright 2006 Red Hat Software
 *
 * This software may be freely redistributed under the terms of the GNU
 * General Public License, version 2.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 */

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <strings.h>
#include <string.h>

/* grab the local time and replace the %DATE var with it */
char * xlate_time(const char *dst)
{
	struct tm *lclnow;
	time_t now;
	char *new_dst,*top;
	int x;
	
	//get the time
	if ((top=(char *)malloc(256)) == NULL) 	
		return NULL;
	if ((now = time(NULL)) < 1) 			
		return NULL;
	if ((lclnow = localtime(&now)) == NULL) 	
		return NULL;

	//copy the easy stuff
	new_dst=top;
	while (*dst && (*dst != '%')) *new_dst++ = *dst++;
	
	//translate the date part
	//we output Year-Month-Day-Hour:Minute
	if (*dst == '%'){
		x = sprintf(new_dst,"%d-%02d-%02d-%02d:%02d", lclnow->tm_year+1900, 
				lclnow->tm_mon+1, lclnow->tm_mday, lclnow->tm_hour, 
				lclnow->tm_min);	
		new_dst += x;

		//finish the copy
		dst += 5;  //skip over %DATE
		while (*dst) *new_dst++ = *dst++;
	}
	*new_dst='\0';

	return top;
}

void usage(int rc)
{

	printf("usage: kcp source dest\n");
	printf("       kcp --ssh src user@host:/dst\n");
	printf("       kcp --local src dst\n");
	printf("Will translate any %%DATE command properly\n");
	printf("in the 'dest' variable\n");
	exit(rc);
}

int main(int argc, char *argv[])
{
	char *src, *dst, *new_dst, *ptr;
	char *path;
	int using_ssh=0;
	char *login;
	int status;
	pid_t child;

	if (argc < 4)
		usage(1);

	src = argv[2];
	dst = argv[3];
	if ((new_dst=xlate_time(dst)) == NULL){
		printf("Failed to translate time\n");
		exit(1);
	}

	if (!strcmp(argv[1], "--ssh"))
		using_ssh =1;
	
	/*
	 * Now that we have called xlate_time, new_dst
	 * holds the expanded ssh destination
	 */
	if (using_ssh) {
		login=strdup(new_dst);
		ptr=index(login, ':');
		*ptr++='\0';
		path = ptr;
	} else {
		login = NULL;
		path = new_dst;
	}

	/*
	 *this makes our target directory
	 */
	if ((child = fork()) == 0) {
		/*
		 * child
		 */
		if (using_ssh) {
			if (execlp("ssh", "ssh", "-q", "-o", "BatchMode=yes", "-o",
				"StrictHostKeyChecking=no", login, "mkdir", "-p",
				path, NULL) < 0) {
				perror("Failed to run ssh");
				exit(1);
			}
		} else {
			if (execlp("mkdir", "mkdir", "-p", path, NULL) < 0) {
				perror("Failed to run mkdir");
				exit(1);
			}
		}
	} else {
		/*
		 * parent
		 */
		if (child < 0) {
			perror("Could not fork");
			exit(1);
		}
		wait(&status);
		if (WEXITSTATUS(status) != 0) {
			printf ("%s exited abnormally: error = %d\n",
				using_ssh ? "ssh":"mkdir", WEXITSTATUS(status));
			exit(1);  
		}

	}

	/*
	 * now that we have our directory, lets copy everything over
	 * Note that scp can be used for local copies as well
	 */
	if ((child = fork()) == 0) {
		/*need to include login info if scp to remote host*/
		if (using_ssh)
			path=new_dst; 
		if (execlp("scp", "scp", "-q", "-o", "BatchMode=yes", "-o",
			"StrictHostKeyChecking=no", src, path, NULL) < 0) {
			perror("Failed to run scp\n");
			exit(1);
		}
	} else {
		if (child < 0) {
			perror("Could not fork");
			exit(1);
		}
		wait(&status);
		if (WEXITSTATUS(status) != 0) {
			printf("scp exited abnormally: error = %d\n",
				WEXITSTATUS(status));
			exit(1);
		}
	}
	
	exit(0);	
}
