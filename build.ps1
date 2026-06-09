<#
.SYNOPSIS
    Windows build for the Nucleus self-hosting compiler — the PowerShell
    counterpart of the POSIX Makefile / build.sh flow (Stage 8, Phase F).

.DESCRIPTION
    Mirrors the Linux build exactly, step for step:

        1. compile the REPL shim (src/repl_shim.c) to an object file;
        2. ensure a runnable boot compiler exists (build it from the committed
           Windows boot IR in boot\ if bin\nucleusc.exe is missing/stale);
        3. self-host: the boot compiler emits build\nucleusc.ll from
           src/nucleusc.nuc, which is then linked into build\nucleusc.exe.

    There is no `nucleusc.exe` to begin with on a fresh Windows checkout, so
    the chicken-and-egg is broken exactly as on Linux: a committed boot IR
    (boot\nucleusc-<flavor>.ll, cross-emitted on the Linux host via
    `--target`) is compiled by clang into the first binary. The compiler's own
    functions pass only pointers — there is no aggregate-by-value in its IR —
    so the boot IR is ABI-clean on Win64 even though Win64 aggregate ABI
    lowering itself is not yet implemented (see design\stage8\platform.md).

    Two toolchains are supported (designer answer 10 — both an entirely
    open-source path and the platform default):

        -Toolchain mingw   (default) x86_64-pc-windows-gnu  — clang + LLD/GNU,
                           no Visual Studio required (fully open source).
        -Toolchain msvc              x86_64-pc-windows-msvc — clang driving
                           link.exe/lld-link; needs the MSVC libraries
                           (Visual Studio or Build Tools) on PATH.

    Both paths use `clang` as the compile/link driver, matching the Linux
    flow; only the target triple, the matching boot IR, and the export flag
    differ.

.PARAMETER Toolchain
    'mingw' (default) or 'msvc'. Selects target triple, boot IR, link flags.

.PARAMETER Bootstrap
    After building, recompile the compiler with itself and verify the
    fixed point (stage1.ll == stage2.ll), then check it compiles hello.nuc.

.PARAMETER UpdateBootstrap
    Refresh the committed Windows boot IR for the selected toolchain from the
    freshly built compiler. Run only at a stable milestone (tests green,
    bootstrap verified). The Linux boot IR is refreshed by `make
    update-bootstrap`; this only touches the Windows flavor.

.PARAMETER Clean
    Remove the build\ directory and exit.

.EXAMPLE
    pwsh -File build.ps1                 # default mingw build
    pwsh -File build.ps1 -Toolchain msvc # MSVC build
    pwsh -File build.ps1 -Bootstrap      # build + fixed-point check
#>
[CmdletBinding()]
param(
    [ValidateSet('mingw', 'msvc')]
    [string]$Toolchain = 'mingw',
    [switch]$Bootstrap,
    [switch]$UpdateBootstrap,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Always operate relative to the repository root (this script's directory),
# regardless of the caller's working directory.
$Root  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Build = Join-Path $Root 'build'
$Bin   = Join-Path $Root 'bin'

# Toolchain -> (target triple, committed boot IR, extra link flags).
switch ($Toolchain) {
    'mingw' {
        $Triple   = 'x86_64-pc-windows-gnu'
        $BootIR   = Join-Path $Root 'boot\nucleusc-x86_64-windows-gnu.ll'
        # Export all symbols so the in-process ORC JIT (REPL) can resolve the
        # repl_shim functions, the GNU analogue of Linux `-rdynamic`.
        $LinkFlags = @('-Wl,--export-all-symbols')
    }
    'msvc' {
        $Triple   = 'x86_64-pc-windows-msvc'
        $BootIR   = Join-Path $Root 'boot\nucleusc-x86_64-windows-msvc.ll'
        # link.exe/lld-link have no blanket "-rdynamic"; batch compilation is
        # unaffected, only the REPL/JIT needs exported symbols (carried
        # forward — see platform.md).
        $LinkFlags = @()
    }
}

$NucleuscExe = Join-Path $Build 'nucleusc.exe'
$BootExe     = Join-Path $Bin   'nucleusc.exe'
$ShimObj     = Join-Path $Build 'repl_shim.obj'
$StageLL     = Join-Path $Build 'nucleusc.ll'

function Invoke-Native {
    param([string]$File, [string[]]$Arguments, [string]$RedirectStdout)
    Write-Host ">> $File $($Arguments -join ' ')" -ForegroundColor DarkGray
    if ($RedirectStdout) {
        # Start-Process writes the child's raw stdout bytes to the file. Do NOT
        # use PowerShell `>` here: on Windows PowerShell 5.1 it re-encodes as
        # UTF-16 with a BOM, which corrupts the emitted .ll for clang.
        $p = Start-Process -FilePath $File -ArgumentList $Arguments `
                -NoNewWindow -Wait -PassThru -RedirectStandardOutput $RedirectStdout
        if ($p.ExitCode -ne 0) { throw "$File exited with code $($p.ExitCode)" }
    } else {
        & $File @Arguments
        if ($LASTEXITCODE -ne 0) { throw "$File exited with code $LASTEXITCODE" }
    }
}

function Get-LLVMFlags {
    # llvm-config.exe ships with LLVM on Windows just as on Linux. Capture each
    # group as a flat argument array (whitespace-split, blanks dropped).
    param([string[]]$ConfigArgs)
    $out = & llvm-config @ConfigArgs
    if ($LASTEXITCODE -ne 0) { throw "llvm-config $ConfigArgs failed" }
    return @($out -split '\s+' | Where-Object { $_ -ne '' })
}

if ($Clean) {
    if (Test-Path $Build) { Remove-Item -Recurse -Force $Build }
    Write-Host "cleaned $Build"
    return
}

New-Item -ItemType Directory -Force -Path $Build | Out-Null
New-Item -ItemType Directory -Force -Path $Bin   | Out-Null

# LLVM link inputs (same component set as the Makefile: orcjit core irreader).
$LdFlags   = Get-LLVMFlags @('--ldflags')
$Libs      = Get-LLVMFlags @('--libs', 'orcjit', 'core', 'irreader')
$SystemLib = Get-LLVMFlags @('--system-libs')

function Link-Compiler {
    param([string]$InputIR, [string]$OutputExe)
    $linkArgs = @($InputIR, $ShimObj) + $LdFlags + $Libs + $SystemLib + $LinkFlags + @('-O3', '-o', $OutputExe)
    Invoke-Native -File 'clang' -Arguments $linkArgs
}

# 1. REPL shim.
Invoke-Native -File 'clang' -Arguments @('-std=c11', '-c', (Join-Path $Root 'src\repl_shim.c'), '-o', $ShimObj)

# 2. Ensure a runnable boot compiler. Rebuild from the committed boot IR if the
#    boot exe is absent or cannot execute (e.g. an LLVM shared-lib mismatch).
$needBoot = $true
if (Test-Path $BootExe) {
    try { & $BootExe --help *> $null; if ($LASTEXITCODE -eq 0) { $needBoot = $false } } catch { }
}
if ($needBoot) {
    if (-not (Test-Path $BootIR)) { throw "missing boot IR: $BootIR" }
    Write-Host "bootstrapping $BootExe from $BootIR ..." -ForegroundColor Cyan
    Link-Compiler -InputIR $BootIR -OutputExe $BootExe
}

# 3. Self-host. Pass --target explicitly so the emitted triple is deterministic
#    (independent of how the host LLVM names itself) and matches the committed
#    boot IR — which keeps the Phase-F fixed-point check below honest.
Invoke-Native -File $BootExe -Arguments @("--target=$Triple", '--emit-llvm', (Join-Path $Root 'src\nucleusc.nuc')) -RedirectStdout $StageLL
Link-Compiler -InputIR $StageLL -OutputExe $NucleuscExe
Write-Host "built: $NucleuscExe ($Toolchain / $Triple)" -ForegroundColor Green

if ($UpdateBootstrap) {
    Invoke-Native -File $NucleuscExe -Arguments @("--target=$Triple", '--emit-llvm', (Join-Path $Root 'src\nucleusc.nuc')) -RedirectStdout $BootIR
    Copy-Item $NucleuscExe $BootExe -Force
    Write-Host "updated boot IR: $BootIR" -ForegroundColor Green
}

if ($Bootstrap) {
    Write-Host "=== Stage 2: self-hosted compiler -> nucleusc.nuc ===" -ForegroundColor Cyan
    $Stage2LL  = Join-Path $Build 'stage2.ll'
    $Stage2Exe = Join-Path $Build 'nucleusc-stage2.exe'
    Invoke-Native -File $NucleuscExe -Arguments @("--target=$Triple", '--emit-llvm', (Join-Path $Root 'src\nucleusc.nuc')) -RedirectStdout $Stage2LL
    Link-Compiler -InputIR $Stage2LL -OutputExe $Stage2Exe

    Write-Host "=== Fixed-point test ===" -ForegroundColor Cyan
    if ((Get-FileHash $StageLL).Hash -ne (Get-FileHash $Stage2LL).Hash) {
        Write-Host "FAIL: stage1.ll != stage2.ll" -ForegroundColor Red
        # Show the first divergence to aid debugging.
        $d = Compare-Object (Get-Content $StageLL) (Get-Content $Stage2LL) | Select-Object -First 20
        $d | Format-Table | Out-String | Write-Host
        throw "bootstrap fixed point failed"
    }
    Write-Host "PASS: stage1.ll == stage2.ll" -ForegroundColor Green

    Write-Host "=== Verify stage2 compiles hello.nuc ===" -ForegroundColor Cyan
    $outDir = Join-Path $Build 'out'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $helloExe = Join-Path $outDir 'hello-bootstrap.exe'
    Invoke-Native -File $Stage2Exe -Arguments @((Join-Path $Root 'examples\hello.nuc'), '-o', $helloExe)
    $helloOut = & $helloExe
    $expected = Get-Content (Join-Path $Root 'tests\expected\hello.out') -Raw
    if (($helloOut -join "`n").TrimEnd() -ne $expected.TrimEnd()) {
        Write-Host "FAIL: hello output mismatch" -ForegroundColor Red
        throw "bootstrap hello check failed"
    }
    Write-Host "PASS: bootstrap complete" -ForegroundColor Green
}
