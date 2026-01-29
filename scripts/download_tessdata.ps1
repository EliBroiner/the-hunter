# מוריד את קבצי tessdata (eng, heb) מ-tessdata_fast ל-assets/tessdata
# הרץ מהשורש של הפרויקט: .\scripts\download_tessdata.ps1

$base = "https://github.com/tesseract-ocr/tessdata_fast/raw/main"
$outDir = Join-Path (Join-Path $PSScriptRoot "..") "assets"
$outDir = Join-Path $outDir "tessdata"
$outDir = [System.IO.Path]::GetFullPath($outDir)

if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

foreach ($name in @("eng.traineddata", "heb.traineddata")) {
  $url = "$base/$name"
  $path = Join-Path $outDir $name
  Write-Host "Downloading $name ..."
  Invoke-WebRequest -Uri $url -OutFile $path -UseBasicParsing
  Write-Host "  -> $path"
}
Write-Host "Done. Run 'flutter pub get' and rebuild."
