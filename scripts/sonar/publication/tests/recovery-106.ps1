$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../recovery-106.lib.ps1')
$policy = Get-Content -Raw (Join-Path $PSScriptRoot '../recovery-106.json') | ConvertFrom-Json
$passed = 0

function Test-Rejected([string]$Name, [scriptblock]$Action) {
    # Arrange
    $rejected = $false

    # Act
    try { & $Action } catch { $rejected = $true }

    # Assert
    if (!$rejected) { throw "FAIL ${Name}: invalid evidence was accepted." }
    $script:passed++
    Write-Output "PASS $Name"
}

function Copy-Fixture($Value) { $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json }

# Arrange
$now = [DateTimeOffset]::UtcNow
$sha = 'a' * 40
$context = [pscustomobject]@{
    repository='andregoepel/core'; event='workflow_dispatch'; ref='refs/heads/main'; confirmation='recover-core-1.0.6-symbols'
    sha=$sha; authorizedSha=$sha; workflowSha=$sha; workflowRef='andregoepel/core/.github/workflows/nuget-publish.yml@refs/heads/main'; attempt='1'; runId='77'
}
$run = [pscustomobject]@{
    id=77; run_attempt=1; head_sha=$sha; event='workflow_dispatch'; head_branch='main'; status='in_progress'; workflow_id=394955060
    path='.github/workflows/nuget-publish.yml'; repository=@{id=1312477613}; head_repository=@{id=1312477613}
}
$inventory = [pscustomobject]@{total_count=1;workflow_runs=@($run)}

# Act
Assert-RecoveryContext $context $run $inventory $sha

# Assert
$passed++
foreach ($field in @('repository','event','ref','confirmation','sha','authorizedSha','workflowSha','workflowRef','attempt')) {
    $bad = Copy-Fixture $context
    $bad.$field = 'wrong'
    Test-Rejected "context-$field" { Assert-RecoveryContext $bad $run $inventory $sha }
}
foreach ($field in @('id','run_attempt','head_sha','event','head_branch','status','workflow_id','path')) {
    $bad = Copy-Fixture $run
    $bad.$field = 'wrong'
    Test-Rejected "run-$field" { Assert-RecoveryContext $context $bad $inventory $sha }
}
Test-Rejected 'newer-main' { Assert-RecoveryContext $context $run $inventory ('b' * 40) }
Test-Rejected 'prior-manual-run' { Assert-RecoveryContext $context $run ([pscustomobject]@{total_count=2;workflow_runs=@($run,$run)}) $sha }
Test-Rejected 'truncated-run-list' { Assert-RecoveryContext $context $run ([pscustomobject]@{total_count=2;workflow_runs=@($run)}) $sha }
$bad = Copy-Fixture $run
$bad.head_repository.id = 17
Test-Rejected 'fork-run' { Assert-RecoveryContext $context $bad $inventory $sha }

# Arrange
$pin = $policy.artifacts[1]
$artifact = [pscustomobject]@{
    id=$pin.id; name=$pin.name; expired=$false; expires_at=$now.AddHours(1).ToString('o'); size_in_bytes=100
    digest="sha256:$($pin.sha256)"; workflow_run=@{id=$pin.run;head_sha=$policy.sha;repository_id=$policy.repositoryId;head_repository_id=$policy.repositoryId}
}

# Act
Assert-RecoveryArtifact $artifact $pin $policy $now

# Assert
$passed++
foreach ($change in @(@('id',1),@('name','wrong'),@('expired',$true),@('expires_at',$now.AddSeconds(-1).ToString('o')),@('size_in_bytes',5242881),@('digest','sha256:bad'))) {
    $bad = Copy-Fixture $artifact
    $bad.($change[0]) = $change[1]
    Test-Rejected "artifact-$($change[0])" { Assert-RecoveryArtifact $bad $pin $policy $now }
}
foreach ($field in @('id','head_sha','repository_id','head_repository_id')) {
    $bad = Copy-Fixture $artifact
    $bad.workflow_run.$field = 'wrong'
    Test-Rejected "artifact-origin-$field" { Assert-RecoveryArtifact $bad $pin $policy $now }
}

# Arrange
$historical = Copy-Fixture $run
$historical.id=$policy.preparationRun; $historical.workflow_id=394955059; $historical.event='push'
$historical.head_branch='v1.0.6'; $historical.head_sha=$policy.sha; $historical.status='completed'
$historical | Add-Member conclusion 'success'

# Act
Assert-RecoveryRun $historical $policy.preparationRun 394955059 'push' 'v1.0.6' 'success' $policy

# Assert
$passed++
foreach ($change in @(@('run_attempt',2),@('head_sha',('b'*40)),@('conclusion','failure'),@('head_branch','v1.0.7'))) {
    $bad=Copy-Fixture $historical; $bad.($change[0])=$change[1]
    Test-Rejected "historical-$($change[0])" { Assert-RecoveryRun $bad $policy.preparationRun 394955059 'push' 'v1.0.6' 'success' $policy }
}

# Arrange
$outcome = [pscustomobject]@{
    schemaVersion=1;kind='publication-outcomes';repository=$policy.repository;sha=$policy.sha;publishRunId=[string]$policy.publicationRun
    publishAttempt='1';loginOutcome='success';pushOutcome='failure';authorizesRetry=$false;remoteAcceptanceVerified=$false
    packages=@(
        @{file='AndreGoepel.Core.1.0.6.nupkg';sha256=$policy.packageSha256;cliObservation='cli-success';events=@('started','cli-success')},
        @{file='AndreGoepel.Core.1.0.6.snupkg';sha256=$policy.symbolsSha256;cliObservation='uncertain';events=@('started','uncertain-exit-1')}
    )
}

# Act
Assert-RecoveryOutcomes $outcome $policy

# Assert
$passed++
foreach ($change in @(@('authorizesRetry',$true),@('remoteAcceptanceVerified',$true),@('pushOutcome','success'),@('loginOutcome','failure'),@('sha',('b'*40)))) {
    $bad=Copy-Fixture $outcome; $bad.($change[0])=$change[1]
    Test-Rejected "outcome-$($change[0])" { Assert-RecoveryOutcomes $bad $policy }
}
$bad=Copy-Fixture $outcome; $bad.packages[1].cliObservation='cli-success'
Test-Rejected 'symbols-already-recorded-success' { Assert-RecoveryOutcomes $bad $policy }
$bad=Copy-Fixture $outcome; $bad.packages[0].sha256='wrong'
Test-Rejected 'different-main-package' { Assert-RecoveryOutcomes $bad $policy }

# Arrange
$original=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
$remote=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
$original.Add('lib/net10.0/Core.dll',[byte[]](1,2,3)); $remote.Add('lib/net10.0/Core.dll',[byte[]](1,2,3)); $remote.Add('.signature.p7s',[byte[]](4))

# Act
Assert-RecoveryPayload $original $remote
Assert-RecoverySymbolsAbsent 404

# Assert
$passed+=2
$remote['lib/net10.0/Core.dll']=[byte[]](1,2,4)
Test-Rejected 'tampered-remote-payload' { Assert-RecoveryPayload $original $remote }
foreach ($status in @(200,403,429,500)) { Test-Rejected "symbol-status-$status" { Assert-RecoverySymbolsAbsent $status } }

# Arrange
$receipt=[pscustomobject]@{
    schemaVersion=1;recoveryRun=$context.runId;recoverySha=$sha;releaseSha=$policy.sha;file='AndreGoepel.Core.1.0.6.snupkg';sha256=$policy.symbolsSha256
    remotePackageVerified=$true;symbolsAbsent=$true;authorizesRetry=$false;verifiedAt=$now.ToString('o');readinessExpiresAt=$now.AddMinutes(10).ToString('o')
}

# Act
Assert-RecoveryReceipt $receipt $context $policy $now

# Assert
$passed++
foreach ($change in @(@('file','AndreGoepel.Core.1.0.6.nupkg'),@('sha256','wrong'),@('recoverySha',('b'*40)),@('remotePackageVerified',$false),@('symbolsAbsent',$false),@('authorizesRetry',$true),@('verifiedAt',$now.AddMinutes(-3).ToString('o')),@('verifiedAt',$now.AddMinutes(1).ToString('o')),@('readinessExpiresAt',$now.ToString('o')))) {
    $bad=Copy-Fixture $receipt; $bad.($change[0])=$change[1]
    Test-Rejected "receipt-$($change[0])" { Assert-RecoveryReceipt $bad $context $policy $now }
}
foreach ($case in @(@('success','success','cli-success','cli-success'),@('success','failure','started','uncertain'),@('success','cancelled','started','uncertain'),@('failure','skipped','','not-dispatched'),@('success','failure','','not-dispatched'))) {
    # Act
    $actual=Get-RecoveryObservation $case[0] $case[1] $case[2]

    # Assert
    if ($actual -cne $case[3]) { throw 'Incorrect recovery outcome classification.' }
    $passed++
}
Test-Rejected 'success-without-dispatch' { Get-RecoveryObservation 'success' 'success' '' }
Test-Rejected 'success-without-completion' { Get-RecoveryObservation 'success' 'success' 'started' }
Test-Rejected 'dispatch-without-login' { Get-RecoveryObservation 'failure' 'failure' 'started' }

# Arrange
$workflow=(Get-Content -Raw (Join-Path $PSScriptRoot '../../../../.github/workflows/nuget-publish.yml')).Replace("`r`n","`n")
$jobs=$workflow.Substring($workflow.IndexOf("jobs:`n")+6)

# Act
$jobNames=[regex]::Matches($jobs,'(?m)^  ([a-z][a-z0-9-]*):$')
$normal=$jobs.Substring(0,$jobs.IndexOf('      - name: Check out reviewed recovery'))
$recovery=$jobs.Substring($jobs.IndexOf('      - name: Check out reviewed recovery'))

# Assert
if ($jobNames.Count -ne 1 -or $jobNames[0].Groups[1].Value -cne 'publish') { throw 'The pinned shared verifier requires exactly one publish job.' }
foreach ($section in @(@($normal,'workflow_run'),@($recovery,'workflow_dispatch'))) {
    $steps=@([regex]::Matches($section[0],'(?m)^      - name:.*$'))
    $guards=@([regex]::Matches($section[0],'(?m)^        if:.*$'))
    if ($steps.Count -ne $guards.Count -or @($guards | Where-Object { $_.Value -notmatch "github.event_name == '$($section[1])'" }).Count) {
        throw 'An upload path has an unguarded or wrong-event step.'
    }
}
if ($workflow -notmatch 'vars.CORE_106_SYMBOL_RECOVERY_SHA == github.sha' -or $workflow -notmatch 'environment: nuget-publish') { throw 'Recovery enablement/approval guard missing.' }
$passed+=3

Write-Output "PASS $passed recovery contract cases; no credentials, network or uploads."
