#!/bin/zsh
# usage: sniff.sh start <label> [seconds] | sniff.sh get <label>
V="Windows 11"
case $1 in
 start) prlctl exec "$V" powershell -NoProfile -Command "Start-Process powershell -WindowStyle Hidden -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\razercap\sniff.ps1','-Seconds','${3:-12}','-Out','C:\razercap\s_$2.txt'"; echo "sniffing $2";;
 get) prlctl exec "$V" cmd /c "type C:\\razercap\\s_$2.txt" | tr -d '\r';;
esac
