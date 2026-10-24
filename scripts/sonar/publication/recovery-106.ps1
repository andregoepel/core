[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Verify','Record')][string]$Operation)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'recovery-106.lib.ps1')
$policy = Get-Content -Raw (Join-Path $PSScriptRoot 'recovery-106.json') | ConvertFrom-Json
$root = [IO.Path]::GetFullPath($env:RECOVERY_ROOT)
Assert-Recovery ([IO.Path]::GetDirectoryName($root) -ceq [IO.Path]::GetFullPath($env:RUNNER_TEMP) -and
    [IO.Path]::GetFileName($root) -cmatch '^core-symbol-recovery\.[a-zA-Z0-9]{8}$' -and
    (Test-Path -LiteralPath $root -PathType Container) -and !(Get-Item -LiteralPath $root).LinkType) 'Unexpected recovery evidence directory.'
$context = [pscustomobject]@{
    repository=$env:GITHUB_REPOSITORY; event=$env:GITHUB_EVENT_NAME; ref=$env:GITHUB_REF
    confirmation=$env:RECOVERY_CONFIRMATION; authorizedSha=$env:AUTHORIZED_RECOVERY_SHA
    sha=$env:GITHUB_SHA; workflowSha=$env:GITHUB_WORKFLOW_SHA; workflowRef=$env:GITHUB_WORKFLOW_REF
    runId=$env:GITHUB_RUN_ID; attempt=$env:GITHUB_RUN_ATTEMPT
}

if ($Operation -eq 'Record') {
    $marker = if (Test-Path -LiteralPath (Join-Path $root 'dispatch.txt')) { (Get-Content -Raw (Join-Path $root 'dispatch.txt')).Trim() } else { '' }
    $observation = Get-RecoveryObservation $env:LOGIN_OUTCOME $env:PUSH_OUTCOME $marker
    [ordered]@{
        schemaVersion=1; kind='core-106-symbol-recovery-outcome'; recoveryRun=$context.runId; recoverySha=$context.sha
        releaseSha=$policy.sha; file='AndreGoepel.Core.1.0.6.snupkg'; sha256=$policy.symbolsSha256
        intentArtifact=$env:RECOVERY_INTENT_ID; intentArchiveSha256=$env:RECOVERY_INTENT_DIGEST
        loginOutcome=$env:LOGIN_OUTCOME; pushOutcome=$env:PUSH_OUTCOME; cliObservation=$observation
        recordedAt=[DateTimeOffset]::UtcNow.ToString('o'); authorizesRetry=$false; remoteAcceptanceVerified=$false
    } | ConvertTo-Json | Set-Content -Encoding utf8NoBOM (Join-Path $root 'outcomes.json')
    exit 0
}

foreach ($name in @('NUGET_API_KEY','NUGET_SYMBOL_API_KEY','NUGET_AUTH_TOKEN','ACTIONS_ID_TOKEN_REQUEST_TOKEN','ACTIONS_ID_TOKEN_REQUEST_URL')) {
    Assert-Recovery (![Environment]::GetEnvironmentVariable($name)) 'Recovery verification must not receive publication credentials.'
}

function Read-GitHub([string]$Route) {
    $json = & gh api "repos/andregoepel/core/$Route"
    Assert-Recovery ($LASTEXITCODE -eq 0) 'GitHub evidence unavailable.'
    ($json -join "`n") | ConvertFrom-Json
}

function Assert-LiveContext {
    $main = Read-GitHub 'git/ref/heads/main'
    $run = Read-GitHub "actions/runs/$($context.runId)"
    $inventory = Read-GitHub 'actions/workflows/394955060/runs?event=workflow_dispatch&per_page=100'
    Assert-RecoveryContext $context $run $inventory $main.object.sha
    $head = & git rev-parse HEAD
    Assert-Recovery ($LASTEXITCODE -eq 0 -and $head -ceq $context.sha) 'Recovery checkout differs from its reviewed revision.'
    & git merge-base --is-ancestor $policy.sha HEAD
    Assert-Recovery ($LASTEXITCODE -eq 0) 'The approved original release is not an ancestor of recovery main.'
    $tag = Read-GitHub 'git/ref/tags/v1.0.6'
    Assert-Recovery ($tag.object.type -ceq 'commit' -and $tag.object.sha -ceq $policy.sha) 'The original lightweight release tag changed.'
}

function Save-GitHubArchive([long]$Id, [string]$Path) {
    $start = [Diagnostics.ProcessStartInfo]::new('gh')
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    foreach ($argument in @('api',"repos/andregoepel/core/actions/artifacts/$Id/zip")) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::Start($start)
    $errorTask = $process.StandardError.ReadToEndAsync()
    $file = [IO.File]::Create($Path)
    try { $process.StandardOutput.BaseStream.CopyTo($file) } finally { $file.Dispose() }
    $process.WaitForExit()
    Assert-Recovery ($process.ExitCode -eq 0) 'Artifact download failed; never replace it with a rebuilt archive.'
    $null = $errorTask.Result
    $process.Dispose()
}

Assert-LiveContext
Assert-RecoveryRun (Read-GitHub "actions/runs/$($policy.preparationRun)") $policy.preparationRun 394955059 'push' 'v1.0.6' 'success' $policy
Assert-RecoveryRun (Read-GitHub "actions/runs/$($policy.publicationRun)") $policy.publicationRun 394955060 'workflow_run' 'main' 'failure' $policy
foreach ($workflow in @(394955059,394955060)) {
    $inventory = Read-GitHub "actions/workflows/$workflow/runs?head_sha=$($policy.sha)&per_page=100"
    $expected = if ($workflow -eq 394955059) { $policy.preparationRun } else { $policy.publicationRun }
    Assert-Recovery ($inventory.total_count -eq 1 -and @($inventory.workflow_runs).Count -eq 1 -and
        $inventory.workflow_runs[0].id -eq $expected -and $inventory.workflow_runs[0].run_attempt -eq 1) 'Original release run inventory changed.'
}

$archives = @{}
foreach ($pin in $policy.artifacts) {
    $metadata = Read-GitHub "actions/artifacts/$($pin.id)"
    Assert-RecoveryArtifact $metadata $pin $policy ([DateTimeOffset]::UtcNow)
    $path = Join-Path $root "$($pin.role).zip"
    if (!(Test-Path -LiteralPath $path)) { Save-GitHubArchive $pin.id $path }
    Assert-Recovery ((Get-RecoveryHash $path) -ceq $pin.sha256) 'Original archive digest mismatch.'
    $archives[$pin.role] = Read-RecoveryZip $path
}
$batch = $archives.batch
Assert-Recovery ($batch.Count -eq 3 -and $batch.ContainsKey('dry-run.json') -and
    $batch.ContainsKey('packages/AndreGoepel.Core.1.0.6.nupkg') -and $batch.ContainsKey('packages/AndreGoepel.Core.1.0.6.snupkg')) 'Unexpected original batch layout.'
Assert-Recovery ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($batch['dry-run.json'])).ToLowerInvariant() -ceq $policy.manifestSha256) 'Historical manifest differs.'
$outcome = [Text.Encoding]::UTF8.GetString($archives.outcomes['outcomes.json']) | ConvertFrom-Json
Assert-RecoveryOutcomes $outcome $policy

$packages = Join-Path $root 'original'
New-Item -ItemType Directory -Force $packages | Out-Null
foreach ($extension in @('nupkg','snupkg')) {
    $file = "AndreGoepel.Core.1.0.6.$extension"
    $path = Join-Path $packages $file
    [IO.File]::WriteAllBytes($path,$batch["packages/$file"])
    $expected = if ($extension -eq 'nupkg') { $policy.packageSha256 } else { $policy.symbolsSha256 }
    Assert-Recovery ((Get-RecoveryHash $path) -ceq $expected) 'Original package bytes differ.'
}
$remote = Join-Path $root 'published.nupkg'
Invoke-WebRequest 'https://api.nuget.org/v3-flatcontainer/andregoepel.core/1.0.6/andregoepel.core.1.0.6.nupkg' -OutFile $remote -TimeoutSec 30
Assert-Recovery ((Get-RecoveryHash $remote) -ceq $policy.signedPackageSha256) 'The signed published package differs from the independently reconciled release.'
Assert-RecoveryPayload (Read-RecoveryZip (Join-Path $packages 'AndreGoepel.Core.1.0.6.nupkg')) (Read-RecoveryZip $remote)
& dotnet nuget verify --all $remote *> (Join-Path $root 'signature.log')
Assert-Recovery ($LASTEXITCODE -eq 0) 'NuGet repository signature validation failed.'
$versions = Invoke-RestMethod 'https://api.nuget.org/v3-flatcontainer/andregoepel.core/index.json' -TimeoutSec 30
Assert-Recovery ($versions.versions -ccontains '1.0.6') 'The accepted main package is not indexed.'
$symbolArchive = Read-RecoveryZip (Join-Path $packages 'AndreGoepel.Core.1.0.6.snupkg')
Assert-Recovery ($symbolArchive.ContainsKey('lib/net10.0/AndreGoepel.Core.pdb') -and
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($symbolArchive['lib/net10.0/AndreGoepel.Core.pdb'])).ToLowerInvariant() -ceq $policy.pdbSha256) 'Original PDB differs.'
$symbolUrl = "https://symbols.nuget.org/download/symbols/AndreGoepel.Core.pdb/$($policy.pdbGuid)FFFFFFFF/AndreGoepel.Core.pdb"
$probe = Invoke-WebRequest $symbolUrl -Headers @{ SymbolChecksum="SHA256:$($policy.pdbChecksum)"; SymbolChecksumValidationSupported='1' } -SkipHttpErrorCheck -TimeoutSec 30
Assert-RecoverySymbolsAbsent ([int]$probe.StatusCode)

$readiness = Read-GitHub "actions/workflows/392994102/runs?branch=main&event=workflow_run&head_sha=$($context.sha)&per_page=100"
Assert-Recovery ($readiness.total_count -eq @($readiness.workflow_runs).Count -and $readiness.total_count -gt 0) 'Incomplete current-main readiness inventory.'
$latest = $readiness.workflow_runs | Sort-Object id -Descending | Select-Object -First 1
$toolPin = Get-Content -Raw 'scripts/sonar/publication-target.json' | ConvertFrom-Json
Assert-Recovery ($env:WORKFLOWS_SONAR_TOOL_SHA -ceq $toolPin.verifierRevision -and $latest.status -ceq 'completed' -and $latest.conclusion -ceq 'success') 'Current main is not ready or the verifier pin differs.'
$before = @(Get-ChildItem artifacts/sonar -Directory -Filter 'nuget-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
& dotnet $env:VERIFIER_DLL --root $env:GITHUB_WORKSPACE --nuget-dry-run --sha $context.sha --version 0.0.0 --readiness-run $latest.id *> (Join-Path $root 'current-main-verification.log')
Assert-Recovery ($LASTEXITCODE -eq 0) 'Fresh current-main verification failed; inspect retained logs.'
$created = @(Get-ChildItem artifacts/sonar -Directory -Filter 'nuget-*' | Where-Object FullName -CNotIn $before)
Assert-Recovery ($created.Count -eq 1) 'Unexpected current-main verification output.'
$fresh = Get-Content -Raw (Join-Path $created[0].FullName 'dry-run.json') | ConvertFrom-Json
Assert-Recovery ($fresh.sha -ceq $context.sha -and $fresh.version -ceq '0.0.0' -and $fresh.readinessRunId -eq $latest.id -and
    $fresh.readinessAttempt -eq $latest.run_attempt -and $fresh.dryRun -and !$fresh.releaseEligible -and
    [DateTimeOffset]$fresh.expiresAt -gt [DateTimeOffset]::UtcNow) 'Fresh readiness receipt differs or expired.'
Assert-LiveContext

$receipt = [pscustomobject][ordered]@{
    schemaVersion=1; recoveryRun=$context.runId; recoverySha=$context.sha; releaseSha=$policy.sha
    file='AndreGoepel.Core.1.0.6.snupkg'; sha256=$policy.symbolsSha256
    policySha256=(Get-RecoveryHash (Join-Path $PSScriptRoot 'recovery-106.json'))
    readinessRun=$latest.id; readinessAttempt=$latest.run_attempt; readinessExpiresAt=$fresh.expiresAt
    verifiedAt=[DateTimeOffset]::UtcNow.ToString('o'); remotePackageVerified=$true; symbolsAbsent=$true; authorizesRetry=$false
}
Assert-RecoveryReceipt $receipt $context $policy ([DateTimeOffset]::UtcNow)
$receipt | ConvertTo-Json | Set-Content -Encoding utf8NoBOM (Join-Path $root 'verified.json')
$intentPath = Join-Path $root 'intent.json'
if (!(Test-Path -LiteralPath $intentPath)) {
    Assert-Recovery (!$env:RECOVERY_INTENT_ID -and !$env:RECOVERY_INTENT_DIGEST) 'A retained recovery intent is missing locally.'
    $receipt | ConvertTo-Json | Set-Content -Encoding utf8NoBOM $intentPath
} else {
    Assert-Recovery ($env:RECOVERY_INTENT_ID -cmatch '^[1-9][0-9]{0,15}$' -and $env:RECOVERY_INTENT_DIGEST -cmatch '^[a-f0-9]{64}$') 'Retained recovery intent identity is required.'
    $metadata = Read-GitHub "actions/artifacts/$env:RECOVERY_INTENT_ID"
    $pin = [pscustomobject]@{ id=[long]$env:RECOVERY_INTENT_ID; name="core-106-symbol-recovery-intent-$($context.runId)-1"; run=[long]$context.runId; sha256=$env:RECOVERY_INTENT_DIGEST }
    $current = [pscustomobject]@{ sha=$context.sha; repositoryId=1312477613 }
    Assert-RecoveryArtifact $metadata $pin $current ([DateTimeOffset]::UtcNow)
    $archivePath = Join-Path $root 'stored-intent.zip'
    Save-GitHubArchive $pin.id $archivePath
    Assert-Recovery ((Get-RecoveryHash $archivePath) -ceq $pin.sha256) 'Stored recovery intent ZIP digest differs.'
    $stored = Read-RecoveryZip $archivePath
    Assert-Recovery ($stored.Count -eq 1 -and $stored.ContainsKey('intent.json') -and
        [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($stored['intent.json'])).ToLowerInvariant() -ceq (Get-RecoveryHash $intentPath)) 'Stored recovery intent content differs.'
    $intent = Get-Content -Raw $intentPath | ConvertFrom-Json
    Assert-Recovery ($intent.recoveryRun -eq $receipt.recoveryRun -and $intent.recoverySha -ceq $receipt.recoverySha -and
        $intent.releaseSha -ceq $receipt.releaseSha -and $intent.file -ceq $receipt.file -and $intent.sha256 -ceq $receipt.sha256 -and
        $intent.policySha256 -ceq $receipt.policySha256 -and $intent.readinessRun -eq $receipt.readinessRun -and
        $intent.readinessAttempt -eq $receipt.readinessAttempt) 'Recovery intent or readiness was superseded.'
}
Write-Output 'Original release evidence, signed package, missing symbols and fresh current-main readiness verified. No upload performed.'
