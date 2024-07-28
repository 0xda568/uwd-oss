ImpersonateTrustedInstaller() {
	return ImpersonateProcess(GetTrustedInstallerPid())
}

RevertToSelf() {
	return DllCall("Advapi32.dll\RevertToSelf")
}

; https://github.com/winsiderss/systeminformer/blob/master/SystemInformer/runas.c#L2123;
RunAsTrustedInstaller(cmd_line, work_dir := "") {
	static PROCESS_CREATE_PROCESS := 0x80, PROC_THREAD_ATTRIBUTE_PARENT_PROCESS := 0x20000
		 , CREATE_NEW_CONSOLE := 0x10, EXTENDED_STARTUPINFO_PRESENT := 0x80000, CREATE_DEFAULT_ERROR_MODE := 0x4000000

	if not (PID_TI := GetTrustedInstallerPid())
		return false

	if !EnablePrivilege()	; need SeDebugPrivilege to open with PROCESS_CREATE_PROCESS
		return false
	hProcTi := DllCall("OpenProcess", "UInt",PROCESS_CREATE_PROCESS, "Int",false, "UInt",PID_TI, "Ptr")
	if (!hProcTi)
		return false

	VarSetCapacity(PROCESS_INFORMATION, A_PtrSize*2 + 8, 0)
	size := VarSetCapacity(STARTUPINFOEX, A_PtrSize*10 + 32, 0)
	NumPut(size, &STARTUPINFOEX + 0, "UInt")

	DllCall("InitializeProcThreadAttributeList", "Ptr",0, "UInt",1, "UInt",0, "UPtrP",size)
	size := VarSetCapacity(PROC_THREAD_ATTRIBUTE_LIST, size, 0)
	DllCall("InitializeProcThreadAttributeList", "Ptr",&PROC_THREAD_ATTRIBUTE_LIST, "UInt",1, "UInt",0, "UPtrP",size)

	DllCall("UpdateProcThreadAttribute", "Ptr",&PROC_THREAD_ATTRIBUTE_LIST, "UInt",0
		, "UPtr",PROC_THREAD_ATTRIBUTE_PARENT_PROCESS, "PtrP",hProcTi, "UPtr",A_PtrSize, "Ptr",0, "Ptr",0)
	NumPut(&PROC_THREAD_ATTRIBUTE_LIST, &STARTUPINFOEX + A_PtrSize*9 + 32)

	pwork_dir := (work_dir ? &work_dir : 0)	; doesn't work on one line, v1 bug?
	res := DllCall("CreateProcess", "ptr", 0
								  , "str", cmd_line
								  , "ptr", 0, "ptr", 0
								  , "int", false
								  , "uint", CREATE_NEW_CONSOLE|EXTENDED_STARTUPINFO_PRESENT|CREATE_DEFAULT_ERROR_MODE
								  , "ptr", 0, "ptr", pwork_dir
								  , "ptr", &STARTUPINFOEX, "ptr", &PROCESS_INFORMATION)
	last_err := A_LastError

	if (res) {
		DllCall("CloseHandle", "Ptr",NumGet(&PROCESS_INFORMATION + 0))
		DllCall("CloseHandle", "Ptr",NumGet(&PROCESS_INFORMATION + A_PtrSize))
	}
	DllCall("DeleteProcThreadAttributeList", "Ptr",&PROC_THREAD_ATTRIBUTE_LIST)
	DllCall("CloseHandle", "Ptr",hProcTi)

	return res
}

GetTrustedInstallerPid() {
	static SC_MANAGER_CONNECT := 0x1, SC_MANAGER_ENUMERATE_SERVICE := 0x4
	 	 , SERVICE_QUERY_STATUS := 0x4, SERVICE_START := 0x10, SERVICE_RUNNING := 0x4
	 	 , SC_STATUS_PROCESS_INFO := 0

	hSC := DllCall("Advapi32.dll\OpenSCManager", "Ptr",0, "Ptr",0, "UInt",SC_MANAGER_ENUMERATE_SERVICE, "Ptr")
	if (hSC) {

		hTI := DllCall("Advapi32.dll\OpenService", "Ptr",hSC, "Str","TrustedInstaller", "UInt",SERVICE_QUERY_STATUS|SERVICE_START, "Ptr")
		if (hTI) {
			size := VarSetCapacity(SERVICE_STATUS_PROCESS, 36, 0)
			DllCall("Advapi32.dll\QueryServiceStatusEx", "Ptr",hTI, "UInt",SC_STATUS_PROCESS_INFO, "Ptr",&SERVICE_STATUS_PROCESS, "UInt",size, "UIntP",returnLength:=0)

			if (NumGet(&SERVICE_STATUS_PROCESS + 4, "UInt") != SERVICE_RUNNING) {
				DllCall("Advapi32.dll\StartService", "Ptr",hTI, "Ptr",0, "Ptr",0)
				Loop {
					DllCall("Advapi32.dll\QueryServiceStatusEx", "Ptr",hTI, "UInt",SC_STATUS_PROCESS_INFO, "Ptr",&SERVICE_STATUS_PROCESS, "UInt",size, "UIntP",returnLength:=0)
					if (NumGet(&SERVICE_STATUS_PROCESS + 4, "UInt") = SERVICE_RUNNING)
						break
					Sleep 500
					if (A_Index = 10)
						return false
				}
			}
		}
		DllCall("Advapi32.dll\CloseServiceHandle", "Ptr",hTI)
	}
	DllCall("Advapi32.dll\CloseServiceHandle", "Ptr",hSC)

	return hTI ? NumGet(&SERVICE_STATUS_PROCESS + 28, "UInt") : false
}

ImpersonateProcess(ProcessID) {
	static THREAD_DIRECT_IMPERSONATION := 0x0200, SecurityImpersonation := 2

	if (!ProcessID || !EnablePrivilege())
		return false

	tid := GetProcessThreads(ProcessID, true)
	if (!tid)
		return false
	hThread := DllCall("OpenThread", "UInt",THREAD_DIRECT_IMPERSONATION, "Int",false, "UInt",tid, "Ptr")
	if (!hThread)
		return false

	size := VarSetCapacity(SECURITY_QUALITY_OF_SERVICE, 12, 0)
	NumPut(size, &SECURITY_QUALITY_OF_SERVICE+0, "UInt")
	NumPut(SecurityImpersonation, &SECURITY_QUALITY_OF_SERVICE + 4, "Int")
	status := DllCall("ntdll.dll\NtImpersonateThread", "Ptr",DllCall("GetCurrentThread", "Ptr"), "Ptr",hThread, "Ptr",&SECURITY_QUALITY_OF_SERVICE)
	DllCall("CloseHandle", "Ptr",hThread)
	return status = 0
}

GetProcessThreads(ProcessID, bFirstOnly := false) {
    if !(hSnapshot := DllCall("CreateToolhelp32Snapshot", "uint", 0x4, "uint", ProcessID))
        return false

    NumPut(VarSetCapacity(THREADENTRY32, 28, 0), THREADENTRY32, "uint")
    if !(DllCall("Thread32First", "ptr", hSnapshot, "ptr", &THREADENTRY32))
        return false, DllCall("CloseHandle", "ptr", hSnapshot)

    Threads := []
    while (DllCall("Thread32Next", "ptr", hSnapshot, "ptr", &THREADENTRY32)) {
        if (NumGet(THREADENTRY32, 12, "uint") = ProcessID) {
			if (bFirstOnly)
				return NumGet(THREADENTRY32, 8, "uint"), DllCall("CloseHandle", "ptr", hSnapshot)
            Threads.Push(NumGet(THREADENTRY32, 8, "uint"))
		}
	}
    return Threads.Count() ? Threads : false, DllCall("CloseHandle", "ptr", hSnapshot)
}

EnablePrivilege(Name := "SeDebugPrivilege") {
    hProc := DllCall("GetCurrentProcess", "UPtr")
    If DllCall("Advapi32.dll\LookupPrivilegeValue", "Ptr", 0, "Str", Name, "Int64P", LUID := 0, "UInt")
    && DllCall("Advapi32.dll\OpenProcessToken", "Ptr", hProc, "UInt", 32, "PtrP", hToken := 0, "UInt") { ; TOKEN_ADJUST_PRIVILEGES = 32
        VarSetCapacity(TP, 16, 0) ; TOKEN_PRIVILEGES
        , NumPut(1, &TP + 0, "UInt")
        , NumPut(LUID, &TP + 4, "Int64")
        , NumPut(2, &TP + 12, "UInt") ; SE_PRIVILEGE_ENABLED = 2
        , DllCall("Advapi32.dll\AdjustTokenPrivileges", "Ptr", hToken, "UInt", 0, "Ptr", &TP, "UInt", 0, "Ptr", 0, "Ptr", 0, "UInt")
    }
    LastError := A_LastError
    If (hToken)
        DllCall("CloseHandle", "Ptr", hToken)
    Return !(ErrorLevel := LastError)
}