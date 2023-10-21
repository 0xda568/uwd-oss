# uwd-oss
Open source alternative to the Universal Watermark Remover.

# Introduction
This is a sequel to my [Universal Watermark Remover reverse engineering writeup](https://github.com/0xda568/Universal-Watermark-Disabler-Reverse-Engineering). I analyzed the closed source-software and developed my own opensource version of it, which you can find here.

# How does it work?
The batch script utilizes [COM-hijacking](https://www.ired.team/offensive-security/persistence/t1122-com-hijacking) to inject a DLL into the explorer and to persist on the system. The DLL, then hooks [ExtTextOutW](https://learn.microsoft.com/en-us/windows/win32/api/wingdi/nf-wingdi-exttextouta) to suppress the display of the testsigning watermark.

# Compability
Tested on Windows 10 x64. Should also work on Windows 11, x64.
