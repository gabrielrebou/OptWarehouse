[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host " VERIFICADOR E INSTALADOR DE AMBIENTE JULIA" -ForegroundColor Cyan
Write-Host ""

Write-Host "[1/3] Verificando Julia..." -ForegroundColor Yellow

$julia = (Get-Command julia -ErrorAction SilentlyContinue).Source

if (-not $julia) {
winget list --id Julialang.Julia -e *> $null

if ($LASTEXITCODE -ne 0) {
    Write-Host "Julia não encontrado. Instalando..." -ForegroundColor Yellow

    winget install --id Julialang.Julia -e --silent `
        --accept-source-agreements `
        --accept-package-agreements

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERRO] Falha ao instalar Julia." -ForegroundColor Red
        Read-Host "Pressione Enter para sair"
        exit 1
    }
}

$env:Path = [Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
            [Environment]::GetEnvironmentVariable("Path","User")

$julia = (Get-Command julia -ErrorAction SilentlyContinue).Source

if (-not $julia) {
    $julia = Get-ChildItem `
        "$env:LOCALAPPDATA\Programs\Julia*\bin\julia.exe",
        "$env:ProgramFiles\Julia*\bin\julia.exe" `
        -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}


}

if (-not $julia) {
Write-Host "[ERRO] Não foi possível localizar o Julia." -ForegroundColor Red
Read-Host "Pressione Enter para sair"
exit 1
}

Write-Host "Julia encontrado: $julia" -ForegroundColor Green

& $julia --version

if ($LASTEXITCODE -ne 0) {
Write-Host "[ERRO] Julia não pôde ser executado." -ForegroundColor Red
Read-Host "Pressione Enter para sair"
exit 1
}

Write-Host ""
Write-Host "[2/3] Instalando pacotes..." -ForegroundColor Yellow

& $julia -e 'using Pkg; Pkg.add(ARGS)' Plots Graphs HiGHS JuMP Clustering CSV DataFrames StatsPlots 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERRO] Falha ao instalar os pacotes." -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

Write-Host "Pacotes instalados com sucesso!" -ForegroundColor Green

Write-Host ""
Write-Host "[3/3] Validando pacotes..." -ForegroundColor Yellow

& $julia -e 'using Plots, Graphs, HiGHS, JuMP, Clustering, CSV, DataFrames, StatsPlots' 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[ERRO] Falha na validação dos pacotes." -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

Write-Host ""
Write-Host " [SUCESSO] AMBIENTE JULIA CONFIGURADO!" -ForegroundColor Green
Write-Host ""

exit 0