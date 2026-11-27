<#
.SYNOPSIS
  Gera a pasta portátil "PDF PRO Willian" para Windows 11 x64 (e o .zip dela).

.DESCRIPTION
  Compila pdfcraft.exe (alvo x86_64-pc-windows-msvc, CRT estático: não precisa do Visual C++
  Redistributable) e monta, em dist\PDF PRO Willian\:

    PDF PRO Willian.exe   o aplicativo
    portable.txt          liga o modo portátil: configurações, logs e recuperação ficam em
                          PdfCraftData\ ao lado do .exe, nada vai para %APPDATA%
    models\               modelos de OCR (pulados com -SkipModels)
    LICENSE-*, NOTICE     licenças do projeto

  Requisitos: Rust (rustup, toolchain MSVC) e as "Build Tools para Visual Studio" com o
  componente "Desenvolvimento para desktop com C++" (inclui o Windows SDK). Para o aws-lc também
  é preciso o NASM no PATH. Internet para baixar as dependências do cargo e os modelos de OCR.

  Para ter a interface em português (e outros idiomas), aponte CRAFT_I18N_DIR para um checkout de
  https://github.com/storytold/craft-i18n no commit que está em craft-i18n.rev. Sem isso o
  aplicativo compila e funciona, mas só em inglês.

.EXAMPLE
  pwsh packaging\windows\build-portable-willian.ps1
  pwsh packaging\windows\build-portable-willian.ps1 -SkipBuild -SkipModels
#>
param(
  [switch] $SkipBuild,
  [switch] $SkipModels,
  [string] $Dist = ''
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $Dist) { $Dist = Join-Path $Root 'dist' }
$Target = 'x86_64-pc-windows-msvc'
$AppName = 'PDF PRO Willian'

function Invoke-Native([string] $What, [scriptblock] $Block) {
  Write-Output "==> $What"
  & $Block
  if ($LASTEXITCODE -ne 0) { throw "$What falhou com o código $LASTEXITCODE" }
}

Push-Location $Root
try {
  if (-not $SkipBuild) {
    # CRT estático, só para o alvo (não afeta build scripts nem proc-macros do host).
    $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS = '-C target-feature=+crt-static'
    # Falha o build (em vez de só avisar) se o ícone/VERSIONINFO não puder ser embutido.
    $env:PDFCRAFT_REQUIRE_WINRES = '1'
    Invoke-Native 'rustup target add' { rustup target add $Target }
    Invoke-Native "cargo build ($Target)" { cargo build --release --locked -p pdfcraft --target $Target }
  }

  $TargetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $Root 'target' }
  $Exe = Join-Path $TargetDir "$Target\release\pdfcraft.exe"
  if (-not (Test-Path $Exe)) { throw "não encontrei $Exe (compile primeiro, sem -SkipBuild)" }

  # Cabeçalho PE: precisa ser x64 (0x8664) e GUI (subsystem 2), para não abrir janela de console.
  $bytes = [System.IO.File]::ReadAllBytes($Exe)
  $pe = [BitConverter]::ToInt32($bytes, 0x3C)
  $machine = [BitConverter]::ToUInt16($bytes, $pe + 4)
  $subsystem = [BitConverter]::ToUInt16($bytes, $pe + 0x5C)
  if ($machine -ne 0x8664) { throw "o executável não é x64 (machine 0x$('{0:X}' -f $machine))" }
  if ($subsystem -ne 2) { throw "o executável não é um aplicativo GUI (subsystem $subsystem)" }
  Write-Output 'ok: x64, aplicativo GUI'

  $Pkg = Join-Path $Dist $AppName
  Remove-Item -Recurse -Force $Pkg -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $Pkg | Out-Null
  Copy-Item $Exe (Join-Path $Pkg "$AppName.exe")
  Copy-Item (Join-Path $PSScriptRoot 'portable.txt') $Pkg
  foreach ($f in 'LICENSE-MIT', 'LICENSE-APACHE', 'NOTICE') { Copy-Item (Join-Path $Root $f) $Pkg }
  Copy-Item (Join-Path $Root 'assets\app-icon\LICENSE-document.txt') $Pkg

  if (-not $SkipModels) {
    # Modelos de OCR (verificados por SHA-256); o app procura em models\ ao lado do .exe.
    $Models = Join-Path $Pkg 'models'
    New-Item -ItemType Directory -Force -Path $Models | Out-Null
    Invoke-Native 'cargo xtask models' { cargo xtask models $Models }
    Remove-Item -Force (Join-Path $Models '*.part') -ErrorAction SilentlyContinue
  }

  $Zip = Join-Path $Dist "$($AppName -replace ' ', '-')-portable-win11-x64.zip"
  Remove-Item -Force $Zip -ErrorAction SilentlyContinue
  Compress-Archive -Path $Pkg -DestinationPath $Zip
  Write-Output "Pasta: $Pkg"
  Write-Output "Zip:   $Zip"
} finally {
  Pop-Location
}
