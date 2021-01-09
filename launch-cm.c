#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <dirent.h>
#include <string.h>

static int has_touch_screen(void)
{
    DIR *dir;
    struct dirent *ent;
    char filename[PATH_MAX];
    int ret = 0;
    
    dir = opendir("/sys/class/input");
    if (!dir)
        return 0;
        
    do {
        FILE *file;
        char line[PATH_MAX];
        ent = readdir(dir);
        if (!ent)
            break;
        sprintf(filename, "/sys/class/input/%s/capabilities/abs", ent->d_name);
        file = fopen(filename, "r");
        if (!file)
            continue;
        line[0] = 0;
        fgets(line, 4096, file);
        fclose(file);
        if (line[0] == '1')
            ret = 1;
    
    } while (ent != NULL);
    closedir(dir);
    
    return ret;
}


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
    
        /* If we're not on a touch screen, NULL out the --touch parameter */
        if (!has_touch_screen()) {
            if (argc > 2 && strcmp(argv[2], "--touch") == 0) 
                argv[2] = "";
        }
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