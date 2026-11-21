$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public static class RzS {
 [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_SetFeature(SafeFileHandle h, byte[] b, int l);
 [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] b, int l);
 [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
}
"@
$key='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{4d1e55b2-f16f-11cf-88cb-001111000030}'
$n=Get-ChildItem $key | % PSChildName | ? { $_ -match 'VID_1532&PID_00E2&MI_03' } | select -First 1
$h=[RzS]::CreateFileW('\\?\'+$n.Substring(4),0,3,[IntPtr]::Zero,3,0,[IntPtr]::Zero)
$out=New-Object Collections.Generic.List[string]
foreach($line in Get-Content 'C:\razercap\sweep.txt'){
  $p=$line.Split(','); $c=[byte]$p[0]; $i=[byte]$p[1]; $sz=[byte]$p[2]
  $res='nores'
  for($try=0;$try -lt 6;$try++){
    $r=New-Object byte[] 91; $r[2]=0x1f; $r[6]=$sz; $r[7]=$c; $r[8]=$i; $r[9]=1
    $x=0; for($k=3;$k -lt 89;$k++){$x=$x -bxor $r[$k]}; $r[89]=$x
    if(-not [RzS]::HidD_SetFeature($h,$r,91)){ Start-Sleep -Milliseconds 20; continue }
    Start-Sleep -Milliseconds 25
    $o=New-Object byte[] 91
    for($w=0;$w -lt 8;$w++){ [void][RzS]::HidD_GetFeature($h,$o,91); if($o[1] -ne 1){break}; Start-Sleep -Milliseconds 10 }
    if($o[2] -eq 0x1f -and $o[7] -eq $c -and $o[8] -eq $i){ $res=('{0:x2} ' -f $o[1]) + (($o[6..([Math]::Min(90,9+[int]$o[6]))] | % { '{0:x2}' -f $_ }) -join ' '); break }
    Start-Sleep -Milliseconds 30
  }
  $out.Add(('{0:x2}:{1:x2} {2}' -f $c,$i,$res))
}
$h.Close(); $out | Set-Content 'C:\razercap\sweep_out.txt'; 'done'
