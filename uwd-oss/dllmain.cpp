#include "pch.h"

#include <stdio.h>
#include <iostream>

#include <string>

// Proxying all needed exports to explorerframe.dll
#pragma comment(linker, "/export:DllCanUnloadNow=explorerframe.DllCanUnloadNow")
#pragma comment(linker, "/export:DllGetClassObject=explorerframe.DllGetClassObject")
#pragma comment(linker, "/export:DllGetVersion=explorerframe.DllGetVersion")

UCHAR origOpsW[12] = { 0 };
UCHAR patchOpsW[12] = { 0x48, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xe0 };
FARPROC origExtTxtOutW;

const RECT* watermarkRect;

// Function ExtTextOutW is being replaced with
BOOL hookExtTextOutW(HDC hdc, int x, int y, UINT options, const RECT* lprect, LPCWSTR lpString, UINT c, const INT* lpDx) {

    // Copies the original 12 bytes to the address of ExtTextOutW
    WriteProcessMemory(GetCurrentProcess(), origExtTxtOutW, origOpsW, 12, 0);

    BOOL ret = 0;

    if (!lstrcmpW(lpString, L"Test Mode")) {
        watermarkRect = lprect;
    }

    if (lprect == watermarkRect) {
        ret = true;
    }
    else {
        ret = ExtTextOutW(hdc, x, y, options, lprect, lpString, c, lpDx);
    }

    // Hooks the function again before exiting
    WriteProcessMemory(GetCurrentProcess(), origExtTxtOutW, patchOpsW, 12, 0);

    return ret;
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD  ul_reason_for_call, LPVOID lpReserved) {
    switch (ul_reason_for_call) {
    case DLL_PROCESS_ATTACH: {

        origExtTxtOutW = GetProcAddress(GetModuleHandle(L"gdi32.dll"), "ExtTextOutW");

        void* hookPtr = &hookExtTextOutW;
        memcpy_s(patchOpsW + 2, 8, &hookPtr, 8);

        ReadProcessMemory(GetCurrentProcess(), origExtTxtOutW, origOpsW, 12, 0);
        WriteProcessMemory(GetCurrentProcess(), origExtTxtOutW, patchOpsW, 12, 0);

        break;
    }
    case DLL_THREAD_ATTACH:
    case DLL_THREAD_DETACH:
    case DLL_PROCESS_DETACH:
        break;
    }
    return TRUE;
}

