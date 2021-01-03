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
    if (fork() == 0) {
        execv("/usr/local/bin/carbidemotion", argv);    
    } else {
#ifdef FULLSCREEN
        while (1) {
            int ret;
            ret = system("wmctrl -r \"Carbide Motion\" -b toggle,fullscreen");
            if (ret == 0)
                break;
            usleep(500000);
        }
#endif
    }
}