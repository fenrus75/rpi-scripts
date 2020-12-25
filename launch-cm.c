#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    while (1) {
        int ret;
        
        ret = access("/etc/xdg/autostart/piwiz.desktop", F_OK);
        if (ret != 0)
            break;
            
        usleep(500000);
    }
    execv("/usr/local/bin/carbidemotion", argv);    
}