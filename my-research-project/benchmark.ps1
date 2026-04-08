# Configuration
$query = "./dataflow3.ql"
$db = "../my-db"
$iterations = 30
$logFile = "./benchmark_log.txt"
$outputPath = "./results.bqrs"
# New: Folder to store JSON timing data
$logDir = "./evaluator-logs"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir }

Write-Host "Benchmarking 30 Iterations..." -ForegroundColor Cyan

for ($i = 1; $i -le $iterations; $i++) {
    Write-Host "Run $i/30..." -NoNewline
    
    # We add --evaluator-log to get the JSON breakdown of every predicate
    $evalLog = "$logDir/log_$i.json"
    
    $elapsed = Measure-Command {
        & codeql query run --database=$db --output=$outputPath --evaluator-log=$evalLog -v $query 2>&1 | Out-File -FilePath $logFile -Append
    }
    
    Write-Host " Done ($($elapsed.TotalSeconds)s)" -ForegroundColor Green
}