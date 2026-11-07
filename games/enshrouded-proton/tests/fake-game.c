/*
 * Faux enshrouded_server.exe du banc (tests/proton-stop-check.sh), compilé pour
 * Windows par le workflow :
 *   x86_64-w64-mingw32-gcc -O2 -static -s -o enshrouded_server.exe fake-game.c
 * Programme console lancé par le VRAI Proton de l'image : il écrit la ligne
 * « HostOnline » dans le journal, comme Enshrouded, puis attend. À un événement
 * console (Ctrl+C = 0), il note l'événement, « sauvegarde » 2 s, écrit ./saved
 * et sort. Le banc vérifie ainsi que l'arrêt Docker (SIGINT) atteint le jeu à
 * travers tini, bash, le script proton et Wine.
 */
#include <windows.h>
#include <stdio.h>

static void put(const char *path, const char *text)
{
    FILE *f = fopen(path, "w");
    if (f)
    {
        fputs(text, f);
        fclose(f);
    }
}

static BOOL WINAPI on_ctrl(DWORD type)
{
    char buf[32];
    snprintf(buf, sizeof(buf), "%lu\n", (unsigned long)type);
    put("ctrl-event", buf);
    Sleep(2000);
    put("saved", "saved\n");
    ExitProcess(0);
    return TRUE;
}

int main(void)
{
    FILE *log;

    SetConsoleCtrlHandler(on_ctrl, TRUE);
    CreateDirectoryA("logs", NULL);
    log = fopen("logs\\enshrouded_server.log", "a");
    if (log)
    {
        fputs("[Session] 'HostOnline' (up)!\n", log);
        fclose(log);
    }
    for (;;)
        Sleep(1000);
    return 0;
}
