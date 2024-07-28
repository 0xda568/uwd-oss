#Requires AutoHotkey v1.1
#SingleInstance ignore
#NoTrayIcon
#NoEnv
#Include <TrustedInstaller>
#Include <Inject>
SetBatchLines -1

; RequireAdmin
;@Ahk2Exe-UpdateManifest 1, UWD by Dart Vanya
;@Ahk2Exe-Base Unicode 64*, UWD-OSS
;@Ahk2Exe-Base Unicode 32*, UWD-OSS_x86
;@Ahk2Exe-PostExec UPX.exe "%A_WorkFileName%" -q --lzma, 0,, 1, 1

ProgName := "Universal Watermark Disabler OSS"
DllName := "uwd_oss_" (A_Is64bitOS ? "x64" : "x86") ".dll"
ExplorerFrame_reg := "HKLM\SOFTWARE\Classes\CLSID\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\InProcServer32"

if (A_Is64bitOS && A_PtrSize = 4) {
	MsgBox, 48, %ProgName%, You attemping to run 32-bit version of UWD-OSS on 64-bit Windows.`n`nPlease run 64-bit version instead.
	ExitApp, 1
}

bInstalled := false, bSystemDamaged := false, b3rdParty := false

RegRead, Edition, HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion, ProductName
RegRead, BuildReg, HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion, BuildLabEx
RegRead, _proxy_path, %ExplorerFrame_reg%
EnvGet, SystemRoot, SystemRoot
VarSetCapacity(proxy_path, 256 << !!A_IsUnicode)
DllCall("ExpandEnvironmentStrings", "Str",_proxy_path, "Str",proxy_path, "UInt",256, "UInt")

if (proxy_path = SystemRoot "\system32\explorerframe.dll")
	Status := "Ready for installation"
else if (proxy_path = SystemRoot "\system32\" DllName)
	Status := "Installed", bInstalled := true
else if FileExist(proxy_path)
	Status := "Another proxy dll is installed", b3rdParty := true
else
	Status := "System resources are damaged", bSystemDamaged := true

if VerCompare(A_OSVersion, ">=10.0.22000")
	Edition := StrReplace(Edition, "10", "11")

Gui, Add, GroupBox, h95 w330, Status

Gui, Add, Text, xp+8 yp+18 section, Edition:
Gui, Add, Text, ys xs+90 vEdition, %Edition%

Gui, Add, Text, xs ys+18 section, Build (API):
Gui, Add, Text, ys xs+90 vBuildApi, % GetVersionEx()

Gui, Add, Text, xs ys+18 section, Build (Registry):
Gui, Add, Text, ys xs+90 vBuildReg, %BuildReg%

Gui, Add, Text, xs ys+18 section, Status:
Gui, Add, Text, % "ys xs+90 vStatus " (b3rdParty || bSystemDamaged ? "cRed" : "cGreen"), %Status%

Gui, Add, Text, xm+2 ys+28, Dart Vanya, 2024
Gui, Add, Text, xm+2 yp+16, Thanks to PainteR, 0xda568
Gui, Add, Button, xs+212 ys+28 w110 h30 Disabled%bSystemDamaged% Default gInstall vButInstall, % bInstalled ? "Uninstall" : "Install"

Gui, Show, , %ProgName%
return

Install:
GuiControl, Disable, ButInstall

if (!bInstalled) {
; This hack allows to add only one DLL in compilled EXE
;@Ahk2Exe-Obey U_AddResource64,= %A_PtrSize% = 8 ? "AddResource" : "Nop"
;@Ahk2Exe-Obey U_AddResource86,= %A_PtrSize% = 4 ? "AddResource" : "Nop"
;@Ahk2Exe-%U_AddResource64% uwd_oss_x64.dll
;@Ahk2Exe-%U_AddResource86% uwd_oss_x86.dll
	if (A_IsCompiled)
		ExtractScriptResource(SystemRoot "\System32\" DllName, DllName,, true)
	else
		FileCopy, %DllName%, % SystemRoot "\System32\" DllName, 1
}
if ImpersonateTrustedInstaller() {
	RegWrite, REG_EXPAND_SZ, %ExplorerFrame_reg%,, % "%SystemRoot%\System32\" (!bInstalled ? DllName : "explorerframe.dll")
	if (!ErrorLevel)
		bInstalled := !bInstalled
	RevertToSelf()
}
else {
	GuiControl, Enable, ButInstall
	return
}

GuiControl, , Status, % bInstalled ? "Installed" : "Ready for installation"
Gui, Font, cGreen
GuiControl, Font, Status
GuiControl, , ButInstall, % bInstalled ? "Uninstall" : "Install"
GuiControl, Enable, ButInstall

progman := DllCall("GetShellWindow", "Ptr")
WinGet, explorerPID, PID, % "ahk_id " progman
if (explorerPID) {
	res := 1
	try {
		if (bInstalled)
			res := Inject(explorerPID, SystemRoot "\System32\" DllName)
		else {
			for proc in ComObjGet("winmgmts:").ExecQuery("Select * from Win32_Process WHERE Name='explorer.exe'") {
				if (proc.ExecutablePath = A_WinDir "\explorer.exe") {
					DllUnInject(proc.ProcessId, DllName)
				}
			}
		}
	}
	if (!bInstalled && res)
		FileDelete, % SystemRoot "\System32\" DllName

	if (res && explorerPID) {
		; SWP_NOACTIVATE|SWP_NOSIZE|SWP_NOMOVE|SWP_NOZORDER|SWP_NOOWNERZORDER|	SWP_HIDEWINDOW
		DllCall("SetWindowPos", "Ptr",progman, "Ptr",0, "Int",0, "Int",0, "Int",0, "Int",0, "UInt",0x0010|0x0001|0x0002|0x0004|0x0200|0x0080)
		; SWP_SHOWWINDOW
		DllCall("SetWindowPos", "Ptr",progman, "Ptr",0, "Int",0, "Int",0, "Int",0, "Int",0, "UInt",0x0010|0x0001|0x0002|0x0004|0x0200|0x0040)
		; RDW_ERASE|RDW_INVALIDATE|RDW_UPDATENOW
		; DllCall("RedrawWindow", "Ptr",progman, "Ptr",0, "Ptr",0, "UInt",4|1|256)

		WinGet, workers, List, ahk_class WorkerW ahk_pid %explorerPID%
		Loop % workers {
			DllCall("SetWindowPos", "Ptr",workers%A_Index%, "Ptr",0, "Int",0, "Int",0, "Int",0, "Int",0, "UInt",0x0010|0x0001|0x0002|0x0004|0x0200|0x0080)
			DllCall("SetWindowPos", "Ptr",workers%A_Index%, "Ptr",0, "Int",0, "Int",0, "Int",0, "Int",0, "UInt",0x0010|0x0001|0x0002|0x0004|0x0200|0x0040)
			; DllCall("RedrawWindow", "Ptr",progman, "Ptr",0, "Ptr",0, "UInt",4|1|256)
		}
	}
}

; try if ((pDesktopWallpaper := ComObjCreate("{C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD}", "{B92B56A9-8B55-4E14-9A89-0199BBB6F93B}"))) {
; 	DllCall(NumGet(NumGet(pDesktopWallpaper+0)+16*A_PtrSize), "Ptr", pDesktopWallpaper, "Ptr", 0, "UInt", 0) ; IDesktopWallpaper::AdvanceSlideshow - https://msdn.microsoft.com/en-us/library/windows/desktop/hh706947(v=vs.85).aspx
; 	ObjRelease(pDesktopWallpaper)
; }
return

GuiClose:
GuiEscape:
ExitApp

GetVersionEx() {
	size := VarSetCapacity(OSVERSIONINFOEX, A_IsUnicode ? 284 : 156), NumPut(size, &OSVERSIONINFOEX+0, "UInt")
	if DllCall("kernel32.dll\GetVersionEx", "Ptr",&OSVERSIONINFOEX)
		return NumGet(&OSVERSIONINFOEX+4, "UInt") "." NumGet(&OSVERSIONINFOEX+8, "UInt") "." NumGet(&OSVERSIONINFOEX+12, "UInt")
}

ExtractScriptResource(OutFile, Name, Type := 10, bOverwrite := false)
{
	; originally posted by Lexikos, modified by HotKeyIt
	; http://www.autohotkey.com/forum/post-516086.html#516086
	lib := DllCall("GetModuleHandle", "Ptr",0, "Ptr")
	res := DllCall("FindResource", "Ptr",lib, "Str",Name, "Ptr",Type, "Ptr")
	if (res) {
		if (!bOverwrite && FileExist(OutFile))
			return true
		DataSize := DllCall("SizeofResource", "Ptr",lib, "Ptr",res)
		hresdata := DllCall("LoadResource", "Ptr",lib, "Ptr",res, "Ptr")
		presdata := DllCall("LockResource", "Ptr",hresdata, "Ptr")
		rFile := FileOpen(OutFile, "w")
		if (rFile) {
			rFile.RawWrite(presdata+0, DataSize)
			rFile.Close
			return true
		}
	}
    return false
}