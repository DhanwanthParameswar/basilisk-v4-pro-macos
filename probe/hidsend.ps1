param([string]$Hex = "")
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public static class RzH {
 [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_SetFeature(SafeFileHandle h, byte[] b, int l);
 [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] b, int l);
 [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
}
"@
$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{4d1e55b2-f16f-11cf-88cb-001111000030}'
$names = Get-ChildItem $key | % PSChildName | ? { $_ -match 'VID_1532&PID_00E2' }
foreach ($n in $names) {
  $p = '\\?\' + $n.Substring(4)
  $h = [RzH]::CreateFileW($p, 0, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
  if ($h.IsInvalid) { "open fail $([Runtime.InteropServices.Marshal]::GetLastWin32Error()) $n"; continue }
  $r = New-Object byte[] 91; $r[2]=0x1f; $r[6]=2; $r[8]=0x81
  $c=0; for($i=3;$i -lt 89;$i++){$c=$c -bxor $r[$i]}; $r[89]=$c
  if ([RzH]::HidD_SetFeature($h,$r,91)) {
    Start-Sleep -Milliseconds 60; $o=New-Object byte[] 91; [void][RzH]::HidD_GetFeature($h,$o,91)
    "OK $n"; ($o[1..12] | % { '{0:x2}' -f $_ }) -join ' '
  } else { "set fail $([Runtime.InteropServices.Marshal]::GetLastWin32Error()) $n" }
  $h.Close()
}
