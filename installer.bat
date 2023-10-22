@echo off

echo +------------------------------------------------------------+
echo ^|                                                            ^|
echo ^|                    uwd-oss installer                       ^|
echo ^|                                                            ^|
echo +------------------------------------------------------------+
echo:

>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"

if '%errorlevel%' NEQ '0' (
    echo Requesting administrative privileges...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    set params = %*:"=""
    echo UAC.ShellExecute "cmd.exe", "/c %~s0 %params%", "", "runas", 1 >> "%temp%\getadmin.vbs"

    "%temp%\getadmin.vbs"
    del "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    pushd "%CD%"
    CD /D "%~dp0"
setlocal enabledelayedexpansion

if not exist %SystemRoot%\System32\uwd-oss.dll (
	
	echo ^> uwd-oss.dll not found in System32, starting setup.
	
	echo ^> Copying uwd-oss.dll into C:\Windows\System32...
	copy .\uwd-oss.dll %SystemRoot%\System32\ >nul
	
	if not exist %SystemRoot%\System32\uwd-oss.dll (
		echo [-] Error while copying uwd-oss.dll.
		echo ^> Cleaning up and exiting...
		goto end
	)
	
	echo [+] Copied successfuly.
	
	echo ^> Changing registry ACL...
	set TEMPFILE=%tmp%\owd-oss.tmp
	echo \registry\machine\software\classes\clsid\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\InProcServer32 [17 1] > %TEMPFILE%
	regini %TEMPFILE%
	
	if '!errorlevel!' NEQ '0' (
		echo [-] Error while modifying registry ACL.
		echo ^> Cleaning up and exiting...
		del /f "%SystemRoot%\\System32\\uwd-oss.dll" >nul 
		goto end
	)
	
	echo [+] Changed registry ACL
	
	echo ^> Changing registry explorerframe COM Server...
	reg add HKLM\SOFTWARE\Classes\CLSID\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\InProcServer32 /t REG_EXPAND_SZ /ve /d %SystemRoot%\System32\uwd-oss.dll /f >nul
	
	reg query HKLM\SOFTWARE\Classes\CLSID\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\InProcServer32 /ve | findstr /l %SystemRoot%\\System32\\uwd-oss.dll >nul
	
	if '!errorlevel!' NEQ '0' (
		echo [-] Error while modifying registry.
		echo ^> Cleaning up and exiting...
		del /f "%SystemRoot%\\System32\\uwd-oss.dll" >nul
		goto end
	)
	
	echo [+] Modified registry successfuly.
) else (

	echo ^> uwd-oss.dll found in System32, uninstalling.
	
	echo ^> Removing %SystemRoot%\System32\uwd-oss.dll...
	del /f "%SystemRoot%\\System32\\uwd-oss.dll" >nul
	
	if exist %SystemRoot%\System32\uwd-oss.dll (
		echo [-] Error while removing %SystemRoot%\System32\uwd-oss.dll
	)
	
	echo [+] Removed uwd-oss.dll
	
	reg add HKLM\SOFTWARE\Classes\CLSID\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\InProcServer32 /t REG_EXPAND_SZ /ve /d %SystemRoot%\System32\explorerframe.dll /f >nul
	
	reg query HKLM\SOFTWARE\Classes\CLSID\{ab0b37ec-56f6-4a0e-a8fd-7a8bf7c2da96}\InProcServer32 /ve | findstr /l %SystemRoot%\\System32\\explorerframe.dll >nul
	if '%errorlevel%' NEQ '0' (
		echo [-] Error while modifying registry.
	)	
	
	echo [+] Reverted changes to registry.
)

echo ^> Restarting explorer...
taskkill /IM "explorer.exe" /F >nul
explorer

echo [+] Done.
exit /B

:end
echo [-] Exiting.
