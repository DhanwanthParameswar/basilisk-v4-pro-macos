Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices;
public static class PA { [DllImport("kernel32.dll")] public static extern bool IsWow64Process2(IntPtr h, out ushort p, out ushort n);
 [DllImport("kernel32.dll")] public static extern IntPtr OpenProcess(uint a, bool i, int id); }
"@
Get-Process | ? { $_.Path -match 'Razer' } | % {
  $h=[PA]::OpenProcess(0x1000,$false,$_.Id); $m=0;$n=0; [void][PA]::IsWow64Process2($h,[ref]$m,[ref]$n)
  $f=[IO.File]::ReadAllBytes($_.Path)[0..1023]; $pe=[BitConverter]::ToInt32($f,0x3c); $mach=[BitConverter]::ToUInt16($f,$pe+4)
  '{0,-6} {1,-40} machine=0x{2:x4} {3}' -f $_.Id,$_.Name,$mach,$_.Path
}
