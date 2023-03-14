"C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn\sqlcmd" -S localhost -i d:\Backup\sqlbackupscript.sql
set today=%date:~6,4%%date:~3,2%%date:~0,2%
mkdir f:\Backups\%today%
move f:\backups\*.bak f:\Backups\%today%
echo sql backup of %date% is stored in f:\backup\%today% folder
d:\backup\ps.bat
Pause
