# run_all_connectors.ps1
#
# WHY THIS SCRIPT EXISTS:
#   `codeql database analyze` is only for alert-style queries (`@kind
#   problem`, `path-problem`). Our `all_connectors.ql` is `@kind table` -
#   it produces one row per connector with custom columns. For that, the
#   correct invocation is a two-step pipeline: `codeql query run` to
#   produce a BQRS (CodeQL's binary result format) and `codeql bqrs
#   decode` to convert it to the pipe-separated file the Python pipeline
#   consumes.
#
#   Wrapping both steps in one script prevents everyone re-discovering
#   that `database analyze --format=csv` fails with
#   "Unknown kind Table [UNSUPPORTED_KIND]".
#
# USAGE:
#   ./run_all_connectors.ps1
#   ./run_all_connectors.ps1 -Database ../my-db -Ram 8192
param(
    [string]$Database = "../my-db",
    [string]$Query = "./all_connectors.ql",
    [string]$Bqrs = "./results.bqrs",
    [string]$Output = "./tests/final_result.txt",
    [int]$Ram = 16384
)

Write-Host "Running CodeQL query..." -ForegroundColor Cyan
& codeql query run `
    --database=$Database `
    --output=$Bqrs `
    --ram=$Ram `
    $Query
if ($LASTEXITCODE -ne 0) {
    Write-Host "Query evaluation failed (exit code $LASTEXITCODE)." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "Decoding BQRS to CSV..." -ForegroundColor Cyan
& codeql bqrs decode `
    --format=csv `
    --output=$Output `
    $Bqrs
if ($LASTEXITCODE -ne 0) {
    Write-Host "BQRS decode failed (exit code $LASTEXITCODE)." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "Wrote results to $Output." -ForegroundColor Green
