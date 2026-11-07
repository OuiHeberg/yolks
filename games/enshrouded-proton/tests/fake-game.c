/*
 * Faux enshrouded_server.exe du banc (tests/proton-stop-check.sh), compilé pour
 * Windows par le workflow :
 *   x86_64-w64-mingw32-gcc -O2 -static -s -o enshrouded_server.exe fake-game.c
 * Programme console lancé par le VRAI Proton de l'image : il écrit la ligne
 * « HostOnline » dans le journal, comme Enshrouded, puis attend. À chaque
 * événement console, il ajoute « <type> <ms depuis le lancement> » à
 * ./ctrl-events (Ctrl+C = 0, Ctrl+Break = 1, fermeture = 2). Au premier, il
 * « sauvegarde » pendant SAVE_MS, écrit ./saved et sort. Le banc vérifie ainsi
 * que l'arrêt Docker (SIGINT) atteint le jeu à travers tini, bash, le script
 * proton et Wine, et que rien ne coupe une sauvegarde de plusieurs secondes.
 * Fichiers ouverts en binaire : pas de \r\n de Windows.
 */
#include <windows.h>
#include <stdio.h>

#define SAVE_MS 8000

static DWORD start_ms;
static volatile LONG saving = 0;

static void write_file(const char *path, const char *mode, const char *text)
{
    FILE *f = fopen(path, mode);
    if (f)
    {
        fputs(text, f);
        fclose(f);
    }
}

static BOOL WINAPI on_ctrl(DWORD type)
{
    char buf[64];
    snprintf(buf, sizeof(buf), "%lu %lu\n", (unsigned long)type, (unsigned long)(GetTickCount() - start_ms));
    write_file("ctrl-events", "ab", buf);
    if (InterlockedExchange(&saving, 1))
        return TRUE; /* déjà en cours : l'événement est seulement noté */
    Sleep(SAVE_MS);
    write_file("saved", "wb", "saved\n");
    ExitProcess(0);
    return TRUE;
}

int main(void)
{
    start_ms = GetTickCount();
    SetConsoleCtrlHandler(on_ctrl, TRUE);
    CreateDirectoryA("logs", NULL);
    write_file("logs\\enshrouded_server.log", "ab", "[Session] 'HostOnline' (up)!\n");
    for (;;)
        Sleep(1000);
    return 0;
}
