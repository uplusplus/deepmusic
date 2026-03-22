[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$base = 'https://musetrainer.github.io/library/scores'
$outDir = 'D:\08_ai\workspace\deepmusic\server\uploads\scores'

$pieces = @(
  @{ file = 'Canon_in_D.mxl'; title = 'Canon in D' },
  @{ file = 'moonlight_sonata_3rd_movement.mxl'; title = 'Moonlight Sonata 3rd Mvt' },
  @{ file = 'Piano_Sonata_No._11_K._331_3rd_Movement_Rondo_alla_Turca.mxl'; title = 'Rondo alla Turca' },
  @{ file = 'Clair_de_Lune__Debussy.mxl'; title = 'Clair de Lune' },
  @{ file = 'Erik_Satie_-_Gymnopedie_No.1.mxl'; title = 'Gymnopedie No.1' },
  @{ file = 'Chopin_-_Nocturne_Op_9_No_2_E_Flat_Major.mxl'; title = 'Nocturne Op.9 No.2' },
  @{ file = 'Hungarian_Dance_No_5_in_G_Minor.mxl'; title = 'Hungarian Dance No.5' },
  @{ file = 'Happy_Birthday_To_You_Piano.mxl'; title = 'Happy Birthday' },
  @{ file = 'Ode_to_Joy_Easy_variation.mxl'; title = 'Ode to Joy' },
  @{ file = 'Prelude_I_in_C_major_BWV_846_-_Well_Tempered_Clavier_First_Book.mxl'; title = 'Bach Prelude C Major' },
  @{ file = 'Ave_Maria_D839_-_Schubert_-_Solo_Piano_Arrg..mxl'; title = 'Ave Maria (Schubert)' },
  @{ file = 'Chopin_-_Ballade_no._1_in_G_minor_Op._23.mxl'; title = 'Chopin Ballade No.1' },
  @{ file = 'Beethoven_Symphony_No._5_1st_movement_Piano_solo.mxl'; title = 'Beethoven Symphony 5' },
  @{ file = 'Bella_Ciao.mxl'; title = 'Bella Ciao' },
  @{ file = 'Greensleeves_for_Piano_easy_and_beautiful.mxl'; title = 'Greensleeves' },
  @{ file = 'Prlude_Opus_28_No._4_in_E_Minor__Chopin.mxl'; title = 'Chopin Prelude E Minor' },
  @{ file = 'Liebestraum_No._3_in_A_Major.mxl'; title = 'Liebestraum No.3' },
  @{ file = 'La_Campanella_-_Grandes_Etudes_de_Paganini_No._3_-_Franz_Liszt.mxl'; title = 'La Campanella' },
  @{ file = 'G_Minor_Bach_Original.mxl'; title = 'Bach G Minor' },
  @{ file = 'Dance_of_the_sugar_plum_fairy.mxl'; title = 'Dance of the Sugar Plum Fairy' }
)

$downloaded = 0
foreach ($p in $pieces) {
  $url = "$base/$($p.file)"
  $mxlPath = Join-Path $outDir $p.file
  $xmlName = ($p.file -replace '\.mxl$', '.xml')
  $xmlPath = Join-Path $outDir $xmlName
  
  if (Test-Path $xmlPath) { Write-Host "SKIP  $($p.title)"; continue }
  
  try {
    Invoke-WebRequest -Uri $url -OutFile $mxlPath -UseBasicParsing -ErrorAction Stop -TimeoutSec 15
    
    # MXL is ZIP format - rename to .zip for Expand-Archive
    $zipPath = $mxlPath -replace '\.mxl$', '.zip'
    Rename-Item $mxlPath $zipPath -Force
    
    $tempDir = Join-Path $env:TEMP "mxl_$downloaded"
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force
    
    $containerXml = Join-Path $tempDir 'META-INF\container.xml'
    if (Test-Path $containerXml) {
      $rootFile = ([xml](Get-Content $containerXml -Raw)).container.rootfiles.rootfile.full_path
      $srcPath = Join-Path $tempDir $rootFile
    } else {
      $srcPath = Get-ChildItem $tempDir -Filter "*.xml" -Recurse | Sort-Object Length -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    
    if ($srcPath -and (Test-Path $srcPath)) {
      Copy-Item $srcPath $xmlPath -Force
      $size = (Get-Item $xmlPath).Length
      $content = Get-Content $xmlPath -Raw -Encoding UTF8
      $measures = ([regex]::Matches($content, '<measure[\s>]')).Count
      Write-Host "OK  $($p.title)  ($measures m, $([math]::Round($size/1024))KB)"
      $downloaded++
    }
    
    Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $mxlPath -Force -ErrorAction SilentlyContinue
  } catch {
    Write-Host "FAIL $($p.title): $($_.Exception.Message)"
    Remove-Item $mxlPath -Force -ErrorAction SilentlyContinue
    Remove-Item ($mxlPath -replace '\.mxl$','.zip') -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "`nDownloaded: $downloaded"
