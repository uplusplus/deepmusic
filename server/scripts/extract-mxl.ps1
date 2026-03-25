[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.IO.Compression.FileSystem

$base = 'https://musetrainer.github.io/library/scores'
$outDir = 'D:\08_ai\workspace\deepmusic\server\uploads\scores'

$files = @(
  'Canon_in_D.mxl',
  'Clair_de_Lune__Debussy.mxl',
  'Erik_Satie_-_Gymnopedie_No.1.mxl',
  'Happy_Birthday_To_You_Piano.mxl',
  'Ode_to_Joy_Easy_variation.mxl',
  'Bella_Ciao.mxl',
  'Greensleeves_for_Piano_easy_and_beautiful.mxl',
  'moonlight_sonata_3rd_movement.mxl',
  'Piano_Sonata_No._11_K._331_3rd_Movement_Rondo_alla_Turca.mxl',
  'Chopin_-_Nocturne_Op_9_No_2_E_Flat_Major.mxl',
  'Hungarian_Dance_No_5_in_G_Minor.mxl',
  'Ave_Maria_D839_-_Schubert_-_Solo_Piano_Arrg..mxl',
  'Chopin_-_Ballade_no._1_in_G_minor_Op._23.mxl',
  'Beethoven_Symphony_No._5_1st_movement_Piano_solo.mxl',
  'Prlude_Opus_28_No._4_in_E_Minor__Chopin.mxl',
  'Liebestraum_No._3_in_A_Major.mxl',
  'G_Minor_Bach_Original.mxl',
  'Dance_of_the_sugar_plum_fairy.mxl',
  'Nocturne_No._20_in_C_Minor.mxl',
  'Fur_Elise.mxl',
  'Minuet_in_G_Major_Bach.mxl',
  'Carol_of_the_Bells_easy_piano.mxl'
)

$ok = 0
foreach ($f in $files) {
  $xmlName = $f -replace '\.mxl$','.xml'
  $outXml = Join-Path $outDir $xmlName
  
  # 跳过已有的有效文件
  if ((Test-Path $outXml) -and -not (Get-Item $outXml).PSIsContainer) {
    $sz = (Get-Item $outXml).Length
    if ($sz -gt 1000) { Write-Host "SKIP $f ($([math]::Round($sz/1024))KB)"; $ok++; continue }
  }
  # 清理残留的目录
  if ((Test-Path $outXml) -and (Get-Item $outXml).PSIsContainer) { Remove-Item $outXml -Recurse -Force }
  
  $mxl = "D:\temp\_mxl_$ok.mxl"
  $td = "D:\temp\_mxl_e_$ok"
  
  try {
    $wc = New-Object System.Net.WebClient
    $wc.DownloadFile("$base/$f", $mxl)
    
    if (Test-Path $td) { Remove-Item $td -Recurse -Force }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($mxl, $td)
    
    # 找最大的XML文件 (跳过META-INF)
    $xmlFile = Get-ChildItem $td -Filter "*.xml" -Recurse -File |
      Where-Object { $_.FullName -notmatch 'META-INF' } |
      Sort-Object Length -Descending | Select-Object -First 1
    
    if ($xmlFile) {
      [System.IO.File]::Copy($xmlFile.FullName, $outXml, $true)
      $sz = (Get-Item $outXml).Length
      Write-Host "OK  $f -> $xmlName ($([math]::Round($sz/1024))KB)"
      $ok++
    }
  } catch {
    Write-Host "FAIL $f : $($_.Exception.Message.Substring(0,[Math]::Min(40,$_.Exception.Message.Length)))"
  }
  
  Remove-Item $td -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item $mxl -Force -ErrorAction SilentlyContinue
}

Write-Host "`nDone: $ok files"
Write-Host "`nAll XML files:"
Get-ChildItem $outDir -Filter "*.xml" -File | Where-Object { $_.Length -gt 10000 } | Sort-Object Length -Descending |
  Select-Object Name, @{N='KB';E={[math]::Round($_.Length/1024)}}
