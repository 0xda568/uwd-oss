#include "pch.h"
#include "IatHook.h"

// Proxying all needed exports to explorerframe.dll
#pragma comment(linker, "/export:DllCanUnloadNow=explorerframe.DllCanUnloadNow")
#pragma comment(linker, "/export:DllGetClassObject=explorerframe.DllGetClassObject")
#pragma comment(linker, "/export:DllGetVersion=explorerframe.DllGetVersion")

// Force 1-byte alignment
#pragma pack(push, 1)
struct _HOOK_SCRUCT {
#ifdef _WIN64
    const BYTE mov_rax[2] = { 0x48, 0xb8 };
#else // _WIN64
    const BYTE mov_eax = 0xb8;
#endif
    FARPROC func;
    const BYTE jmp[2] = { 0xff, 0xe0 };
} patchOpsW;
#pragma pack(pop)

typedef BOOL(WINAPI* _ExtTextOutW)(HDC, int, int, UINT, const RECT*, LPCWSTR, UINT, const INT*);

PIMAGE_THUNK_DATA iat_entry = NULL;
_ExtTextOutW origExtTxtOutW = NULL;

// Function ExtTextOutW is being replaced with
BOOL hookExtTextOutW(HDC hdc, int x, int y, UINT options, const RECT* lprect, LPCWSTR lpString, UINT c, const INT* lpDx) {
    static WCHAR watermark[3][64];
    static int n = 0;

    HWND hwnd = WindowFromDC(hdc);
    WCHAR className[8];
    if (hwnd)
        GetClassNameW(hwnd, className, ARRAYSIZE(className));

    // Shell32 calls ExtTextOutW on explorer start to draw watermark
    if (n < 3 && lstrlenW(lpString)) {
        lstrcpyW(watermark[n++], lpString);
        return TRUE;
    }
    // Menu -> Next desktop wallpaper - hwnd will be NULL.
    else if ((!hwnd || !lstrcmpW(className, L"WorkerW") || !lstrcmpW(className, L"Progman")) && lstrlenW(lpString)) {
        for (int i = 0; i < n; i++)
            if (!lstrcmpW(lpString, watermark[i]))
                return TRUE;    // remove all types of cached watermark line (tested and work for Test Mode, Safe Mode)
    }

    // Call original ExtTxtOutW function
    return origExtTxtOutW(hdc, x, y, options, lprect, lpString, c, lpDx);
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD  ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH: {

        WCHAR moduleName[64] = {};
        GetModuleBaseNameW(GetCurrentProcess(), NULL, moduleName, ARRAYSIZE(moduleName));
        if (lstrcmpiW(moduleName, L"explorer.exe"))
            return FALSE;   // don't allow load to non explorer processes

        HWND hShellWnd = GetShellWindow();
        DWORD pid;
        if (hShellWnd) {
            GetWindowThreadProcessId(hShellWnd, &pid);
            if (pid != GetCurrentProcessId())
                return TRUE;    // don't install hook on separate explorer processes (if we block load here new process doesn't start at all)
        }

        // Searching Shell32 IAT for gdi32.dll!ExtTextOutW
        HMODULE hShell32 = GetModuleHandle(L"Shell32.dll");
        if (hShell32)
            iat_entry = FindIatThunkInModule(hShell32, "gdi32.dll", "ExtTextOutW");

        if (iat_entry) {
            // Saving original function
            origExtTxtOutW = (_ExtTextOutW)iat_entry->u1.Function;
            DWORD oldProt;
            VirtualProtect(iat_entry, sizeof(iat_entry), PAGE_READWRITE, &oldProt);
            // Writing address to our hooked function
            iat_entry->u1.Function = (DWORD_PTR)hookExtTextOutW;
            VirtualProtect(iat_entry, sizeof(iat_entry), oldProt, &oldProt);
        }
        break;
    }
    case DLL_THREAD_ATTACH:
    case DLL_THREAD_DETACH:
        break;
    case DLL_PROCESS_DETACH:
        if (iat_entry) {
            DWORD oldProt;
            VirtualProtect(iat_entry, sizeof(iat_entry), PAGE_READWRITE, &oldProt);
            // Unhook function
            InterlockedCompareExchangePointer((PVOID*)&iat_entry->u1.Function, origExtTxtOutW, hookExtTextOutW);
            VirtualProtect(iat_entry, sizeof(iat_entry), oldProt, &oldProt);
        }
        break;
    }
    return TRUE;
}

