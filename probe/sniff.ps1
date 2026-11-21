param([int]$Seconds = 20, [string]$Out = 'C:\razercap\sniff.txt')
Add-Type -TypeDefinition @"
using System; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public static class RzN {
 [DllImport("hid.dll", SetLastError=true)] public static extern bool HidD_GetFeature(SafeFileHandle h, byte[] b, int l);
 [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern SafeFileHandle CreateFileW(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
}
"@
$key='HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{4d1e55b2-f16f-11cf-88cb-001111000030}'
$n=Get-ChildItem $key | % PSChildName | ? { $_ -match 'VID_1532&PID_00E2&MI_03' } | select -First 1
$h=[RzN]::CreateFileW('\\?\'+$n.Substring(4),0,3,[IntPtr]::Zero,3,0,[IntPtr]::Zero)
$sw=[Diagnostics.Stopwatch]::StartNew(); $last=''; $frames=0
$w=New-Object IO.StreamWriter($Out,$false)
while($sw.Elapsed.TotalSeconds -lt $Seconds){
  $o=New-Object byte[] 91
  if([RzN]::HidD_GetFeature($h,$o,91)){
    $sz=[int]$o[6]; $s=(($o[1..([Math]::Min(89,8+$sz))] | % { '{0:x2}' -f $_ }) -join ' ')
    if($s -ne $last){ $last=$s
      if($o[7] -eq 0x0f -and $o[8] -eq 0x03){ $frames++ } else { $w.WriteLine(('{0,7} {1}' -f $sw.ElapsedMilliseconds,$s)); $w.Flush() } }
  }
}
$w.WriteLine("# lighting frames skipped: $frames"); $w.Close(); $h.Close()
