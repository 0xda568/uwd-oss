Inject(PID, dll)
{
	static PROCESS_ALL_ACCESS := 0x1F0FFF, MEM_COMMIT := 0x1000, MEM_RELEASE := 0x8000, PAGE_EXECUTE_READWRITE := 64
		  ,hKernel32 := DllCall("LoadLibrary", "Str", "kernel32.dll", "PTR")
		  ,LoadLibraryW := DllCall("GetProcAddress", "PTR", hKernel32, "AStr", "LoadLibraryW", "PTR")

	hProc := DllCall("OpenProcess", "UInt", PROCESS_ALL_ACCESS, "Int", 0, "UInt", PID, "PTR")
	If !hProc
		throw Exception("Could not open process for PID: " PID ". LastError: " A_LastError, -1)

	nDirLength := VarSetCapacity(nDir, (StrLen(dll)+1) << 1, 0)
	,StrPut(dll, &nDir, "UTF-16")

	If !pBufferRemote := DllCall("VirtualAllocEx", "Ptr", hProc, "Ptr", 0, "PTR", nDirLength, "UInt", MEM_COMMIT, "UInt", PAGE_EXECUTE_READWRITE, "Ptr") {
		DllCall("CloseHandle", "PTR", hProc)
		throw Exception("Could not reseve memory for process: " A_LastError, -1)
	}

	DllCall("WriteProcessMemory", "Ptr", hProc, "Ptr", pBufferRemote, "Ptr", &nDir, "PTR", nDirLength, "Ptr", 0)

	hThread := DllCall("CreateRemoteThread", "PTR", hProc, "PTR", 0, "PTR", 0, "PTR", LoadLibraryW, "PTR", pBufferRemote, "UInt", 0, "PTR", 0, "PTR")
	lasterr := A_LastError

	if (hThread) {
		; waits until the specified object is in the signaled state or the time-out interval elapses
		WaitResult := DllCall("WaitForSingleObject", "ptr", hThread, "uint", 0xFFFFFFFF)
	}

	DllCall("VirtualFreeEx","PTR", hProc, "PTR", pBufferRemote, "PTR", nDirLength, "Uint", MEM_RELEASE)
	DllCall("CloseHandle", "PTR", hProc)
	If !hThread
		throw Exception("Could not load " dll " in remote process: " lasterr, -1)
	return hThread
}

; https://www.autohotkey.com/boards/viewtopic.php?t=68716
DllUnInject(ProcessID, ModuleName)
{
	static TH32CS_SNAPMODULE        := 0x00000008
		 , STANDARD_RIGHTS_REQUIRED := 0x000F0000
		 , SYNCHRONIZE              := 0x00100000
		 , PROCESS_ALL_ACCESS       := (STANDARD_RIGHTS_REQUIRED | SYNCHRONIZE | 0xFFFF)
		 , INFINITE                 := 0xFFFFFFFF
		 , WAIT_FAILED              := 0xFFFFFFFF
		 , WAIT_OBJECT_0            := 0x00000000

	try
	{
		; take a snapshot of all modules in the specified process
		if !(hSnapshot := DllCall("CreateToolhelp32Snapshot", "uint", TH32CS_SNAPMODULE, "uint", ProcessID, "ptr"))
			throw Exception("CreateToolhelp32Snapshot failed: " A_LastError, -1)

		; set the size of the structure before using it.
		NumPut(VarSetCapacity(MODULEENTRY32, (A_PtrSize = 8 ? 568 : 548), 0), MODULEENTRY32, "uint")
		; retrieve information about the first module and exit if unsuccessful
		if !(DllCall("Module32First", "ptr", hSnapshot, "ptr", &MODULEENTRY32))
			throw Exception("Module32First failed: " A_LastError, -1)

		; walk the module list of the process and gets the base address of the module
		while (DllCall("Module32Next", "ptr", hSnapshot, "ptr", &MODULEENTRY32))
			if (ModuleName = StrGet(&MODULEENTRY32+ (A_PtrSize = 8 ? 48 : 32), 256, "cp0")) {
				modBaseAddr := NumGet(MODULEENTRY32, (A_PtrSize = 8 ? 24 : 20), "uptr")
				break
			}

		; exit if module is not found
		if !(modBaseAddr)
			throw Exception("Module not found", -1)

		; opens an existing local process object
		if !(hProcess := DllCall("OpenProcess", "uint", PROCESS_ALL_ACCESS, "int", 0, "uint", ProcessID, "ptr"))
			throw Exception("OpenProcess failed: " A_LastError, -1)

		; retrieves a module handle for the specified module
		if !(hModule := DllCall("GetModuleHandle", "str", "kernel32.dll", "ptr"))
			throw Exception("GetModuleHandle failed: " A_LastError, -1)

		; retrieves the address of an exported function or variable from the specified dynamic-link library (DLL)
		if !(pThreadProc := DllCall("GetProcAddress", "ptr", hModule, "astr", "FreeLibrary", "ptr"))
			throw Exception("GetProcAddress failed with: " A_LastError, -1)

		; creates a thread that runs in the virtual address space of another process
		if !(hThread := DllCall("CreateRemoteThread", "ptr", hProcess, "ptr", 0, "uptr", 0, "ptr", pThreadProc, "ptr", modBaseAddr, "uint", 0, "uint*", 0))
			throw Exception("CreateRemoteThread failed with: " A_LastError, -1)

		; waits until the specified object is in the signaled state or the time-out interval elapses
		if ((WaitResult := DllCall("WaitForSingleObject", "ptr", hThread, "uint", INFINITE)) = WAIT_FAILED)
			throw Exception("WaitForSingleObject failed with: " A_LastError, -1)

		; if the state of the specified object is signaled (thread has terminated)
		if (WaitResult = WAIT_OBJECT_0) {
			; retrieves the termination status of the specified thread
			if !(DllCall("GetExitCodeThread", "ptr", hThread, "uint*", ExitCode))
				throw Exception("GetExitCodeThread failed with: " A_LastError, -1)
		}
	}
	catch exception
	{
		; represents errors that occur during application execution
		throw Exception
	}
	finally
	{
		; cleaning up resources
		if (hThread)
			DllCall("CloseHandle", "ptr", hThread)
		if (hProcess)
			DllCall("CloseHandle", "ptr", hProcess)
		if (hSnapshot)
			DllCall("CloseHandle", "ptr", hSnapshot)
	}

	return ExitCode
}