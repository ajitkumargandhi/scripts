#SET PowerShellDir=C:\Windows\System32\WindowsPowerShell\v1.0
date /t >> d:\backup\disksize.txt
psinfo -d \ |find /i "f:" > d:\backup\disksize.txt
psinfo -d \ |find /i "g:" >> d:\backup\disksize.txt
Powershell.exe -Command "& 'd:\backup\mail.ps1' 
