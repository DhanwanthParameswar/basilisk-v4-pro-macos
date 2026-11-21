$out='C:\razercap\find2.txt'; "start" | Out-File $out
$roots='C:\Program Files\Razer','C:\Program Files (x86)\Razer','C:\Program Files (x86)\Razer Chroma SDK','C:\ProgramData\Razer',"$env:USERPROFILE\AppData\Local\Razer","$env:USERPROFILE\AppData\Roaming\Razer","$env:USERPROFILE\AppData\Roaming\RazerAppEngine"
$a=[Text.Encoding]::ASCII.GetBytes('Basilisk V4 Pro'); $u=[Text.Encoding]::Unicode.GetBytes('Basilisk V4 Pro')
function Has($b,$p){ $n=$b.Length-$p.Length; for($i=[Array]::IndexOf($b,$p[0]); $i -ge 0 -and $i -le $n; $i=[Array]::IndexOf($b,$p[0],$i+1)){ $ok=$true; for($j=1;$j -lt $p.Length;$j++){ if($b[$i+$j] -ne $p[$j]){$ok=$false;break} }; if($ok){return $true} }; return $false }
Get-ChildItem $roots -Recurse -File -ErrorAction SilentlyContinue | ? { $_.Length -lt 150MB -and $_.Extension -notin '.log','.png','.jpg','.webp','.mp4','.ttf','.woff2' } | % {
  try { $b=[IO.File]::ReadAllBytes($_.FullName); if((Has $b $a) -or (Has $b $u)){ ('{0} | {1}' -f [int]($_.Length/1kb), $_.FullName) | Out-File $out -Append } } catch {}
}
"done" | Out-File $out -Append
