[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $InputPattern,

    [Parameter(Mandatory = $true)]
    [string] $Output,

    [ValidateSet('Opaque', 'Alpha')]
    [string] $Mode = 'Opaque',

    [ValidateRange(1, 240)]
    [double] $FrameRate = 30,

    [int] $StartNumber = 0
)

$ErrorActionPreference = 'Stop'
$culture = [Globalization.CultureInfo]::InvariantCulture
$fps = $FrameRate.ToString('0.###', $culture)

foreach ($tool in @('ffmpeg', 'ffprobe')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "Required tool '$tool' was not found. Install FFmpeg and make sure ffmpeg.exe and ffprobe.exe are on PATH."
    }
}

$inputFolder = Split-Path -Parent $InputPattern
if ([string]::IsNullOrWhiteSpace($inputFolder)) { $inputFolder = (Get-Location).Path }
if (-not (Test-Path -LiteralPath $inputFolder)) {
    throw "Input folder does not exist: $inputFolder"
}

$outputPath = [IO.Path]::GetFullPath($Output)
$outputFolder = Split-Path -Parent $outputPath
if (-not (Test-Path -LiteralPath $outputFolder)) {
    New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null
}

$common = @(
    '-hide_banner', '-y',
    '-framerate', $fps,
    '-start_number', "$StartNumber",
    '-i', $InputPattern
)

if ($Mode -eq 'Alpha') {
    if ([IO.Path]::GetExtension($outputPath).ToLowerInvariant() -ne '.mov') {
        throw "Alpha mode requires a .mov output. Example: -Output 'C:\renders\effect-alpha.mov'"
    }
    $encode = @(
        '-vf', 'format=yuva444p10le',
        '-c:v', 'prores_ks', '-profile:v', '4', '-pix_fmt', 'yuva444p10le',
        '-vendor', 'apl0', '-an', $outputPath
    )
    Write-Host 'Encoding ProRes 4444 with an alpha channel. MotionStudio transparency still needs an iOS-device check.' -ForegroundColor Yellow
} else {
    if ([IO.Path]::GetExtension($outputPath).ToLowerInvariant() -ne '.mp4') {
        throw "Opaque mode requires a .mp4 output. Example: -Output 'C:\renders\effect.mp4'"
    }
    $encode = @(
        '-vf', 'format=yuv420p',
        '-c:v', 'libx264', '-preset', 'medium', '-crf', '18',
        '-movflags', '+faststart', '-an', $outputPath
    )
    Write-Host 'Encoding a broadly compatible opaque H.264 MP4.'
}

& ffmpeg @common @encode
if ($LASTEXITCODE -ne 0) {
    throw "FFmpeg failed with exit code $LASTEXITCODE. Check the frame pattern, frame numbers, and image files."
}

Write-Host "`nOutput stream details:"
& ffprobe '-v' 'error' '-select_streams' 'v:0' '-show_entries' 'stream=codec_name,profile,pix_fmt,width,height,duration' '-of' 'default=noprint_wrappers=1' $outputPath
if ($LASTEXITCODE -ne 0) {
    throw "FFprobe could not inspect the output file."
}

Write-Host "`nCreated: $outputPath" -ForegroundColor Green
Write-Host 'Import the output into MotionStudio using Add > Files.'
if ($Mode -eq 'Alpha') {
    Write-Host 'Important: this verifies the encoded file, not alpha preservation in MotionStudio. Check the imported clip over a coloured background before relying on transparency.' -ForegroundColor Yellow
}
