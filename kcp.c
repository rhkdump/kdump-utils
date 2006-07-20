
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

#define BLOCK_SIZE 512
#define SSH_TMP ".kcp-ssh"

/* simple copy routine to copy src to dst */
int copy_core(const char *src, const char *dst)
{
	int bytes, total=0;
	int fd_dst, fd_src;
	char buf[BLOCK_SIZE];

	if ((fd_dst=open(dst,O_RDWR|O_CREAT, 0755)) < 0) 	
		return -1;
	if ((fd_src=open(src,O_RDONLY)) < 0) 		
		return -1;

	while ((bytes=read(fd_src,buf,BLOCK_SIZE)) > 0) {
		if ((bytes=write(fd_dst,buf,bytes)) < 0) 
			break;
		total+=bytes;
	}
	if (bytes < 0) 
		return -1;

	close(fd_dst);
	close(fd_src);

	printf("Total bytes written: %d\n", total);
	return total;
}

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
	printf("       kcp --ssh dest (first time)\n");
	printf("       kcp --ssh src (second time)\n");
	printf("Will translate any %%DATE command properly\n");
	printf("in the 'dest' variable\n");
	exit(rc);
}

int main(int argc, char *argv[])
{
	char *src,*dst, *new_dst, *top;
	char path[256];
	int using_ssh=0;
	char *login;

	if (argc < 3)
		usage(1);

	if (!strncmp(argv[1], "--ssh", 5))
		using_ssh=1;
	else
		src=argv[1];

	dst=argv[2];

	if ((new_dst=xlate_time(dst)) == NULL){
		printf("Failed to translate time\n");
		exit(1);
	}
	top=new_dst;
	
	//Hack for ssh because nash doesn't support variables
	//The idea here is to save the translated date to a file to 
	//be read back later for scp
	if (using_ssh){
		int fd_dst, x;

		if ((fd_dst=open(SSH_TMP, O_RDWR|O_CREAT, 0755)) < 0){
			perror("Failed to open SSH_TMP: ");
			exit(1);
		}
		if ((x=read(fd_dst, path, BLOCK_SIZE)) > 0){
			//second time around
			src=dst;
			path[x]='\0';
			close(fd_dst);
			remove(SSH_TMP);
			execlp("scp", "scp", "-q", "-o", "BatchMode=yes", "-o", 
				"StrictHostKeyChecking=no", src, path, NULL);
			//should never return!!
			perror("Failed to scp: ");
			exit(1);
		}
		//save data for next run of this program
		printf("writing <%s> to file %s\n",top, SSH_TMP);
		if ((write(fd_dst, top, strlen(top))) < 0){
			perror("Failed to write to SSH_TMP: ");
			exit(1);
		}
		close(fd_dst);

		//save the login info
		login=top;
		if ((top=index(login, ':')) == NULL){
			printf("Bad ssh format %s\n", path);
			exit(1);
		}
		*top++='\0';
	}

	//find the directory portion and separate it from the file
	if ((new_dst=rindex(top, '/')) == NULL){
		new_dst=top;  //strange but okay, only the file passed in
		sprintf(path,"%s",new_dst);
	}else{
		*new_dst='\0';
		new_dst++;

		//finish the ssh hack by running mkdir
		if (using_ssh){
			execlp("ssh", "ssh", "-q", "-o", "BatchMode=yes", "-o",
                               "StrictHostKeyChecking=no", login, "mkdir", "-p", 
				top, NULL);
			//should never return!!
			perror("Failed to ssh: ");
			exit(1);
		}
		//make the new directory
		if ((mkdir(top, 0777)) != 0){
			perror("mkdir failed: ");
			exit(1);
		}
		sprintf(path,"%s/%s",top,new_dst);
	}

	if (copy_core(src,path) < 0){
		perror("Failed to write core file: ");
		exit(1);
	}

	return 0;
}
