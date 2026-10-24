$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Recovery([bool]$Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}

function Get-RecoveryHash([string]$Path) {
    Assert-Recovery ((Test-Path -LiteralPath $Path -PathType Leaf) -and !(Get-Item -LiteralPath $Path).LinkType) 'Expected an ordinary evidence file.'
    (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-RecoveryContext($Context, $Run, $Inventory, [string]$Main) {
    Assert-Recovery ($Context.repository -ceq 'andregoepel/core' -and $Context.event -ceq 'workflow_dispatch' -and
        $Context.ref -ceq 'refs/heads/main' -and $Context.confirmation -ceq 'recover-core-1.0.6-symbols' -and
        $Context.sha -cmatch '^[a-f0-9]{40}$' -and $Context.sha -ceq $Main -and $Context.authorizedSha -ceq $Main -and
        $Context.workflowSha -ceq $Main -and $Context.workflowRef -ceq 'andregoepel/core/.github/workflows/nuget-publish.yml@refs/heads/main' -and
        [string]$Context.attempt -ceq '1') 'Recovery requires an explicitly enabled first-attempt manual run on exact current main.'
    Assert-Recovery ($Run.id -eq $Context.runId -and $Run.run_attempt -eq 1 -and $Run.head_sha -ceq $Main -and
        $Run.event -ceq 'workflow_dispatch' -and $Run.head_branch -ceq 'main' -and $Run.status -ceq 'in_progress' -and
        $Run.workflow_id -eq 394955060 -and $Run.path -ceq '.github/workflows/nuget-publish.yml' -and
        $Run.repository.id -eq 1312477613 -and $Run.head_repository.id -eq 1312477613) 'Unexpected recovery run identity.'
    Assert-Recovery ($Inventory.total_count -eq 1 -and @($Inventory.workflow_runs).Count -eq 1 -and
        $Inventory.workflow_runs[0].id -eq $Context.runId -and $Inventory.workflow_runs[0].run_attempt -eq 1) 'A prior manual publisher run exists; recovery must be reviewed again, never replayed.'
}

function Assert-RecoveryArtifact($Actual, $Pin, $Policy, [DateTimeOffset]$Now) {
    Assert-Recovery ($Actual.id -eq $Pin.id -and $Actual.name -ceq $Pin.name -and !$Actual.expired -and
        [DateTimeOffset]$Actual.expires_at -gt $Now -and $Actual.size_in_bytes -gt 0 -and $Actual.size_in_bytes -le 5242880 -and
        $Actual.digest -ceq "sha256:$($Pin.sha256)" -and $Actual.workflow_run.id -eq $Pin.run -and
        $Actual.workflow_run.head_sha -ceq $Policy.sha -and $Actual.workflow_run.repository_id -eq $Policy.repositoryId -and
        $Actual.workflow_run.head_repository_id -eq $Policy.repositoryId) 'Historical artifact identity, digest or availability changed.'
}

function Assert-RecoveryRun($Run, [long]$Id, [long]$Workflow, [string]$Event, [string]$Branch, [string]$Conclusion, $Policy) {
    Assert-Recovery ($Run.id -eq $Id -and $Run.run_attempt -eq 1 -and $Run.head_sha -ceq $Policy.sha -and
        $Run.workflow_id -eq $Workflow -and $Run.event -ceq $Event -and $Run.head_branch -ceq $Branch -and
        $Run.status -ceq 'completed' -and $Run.conclusion -ceq $Conclusion -and
        $Run.repository.id -eq $Policy.repositoryId -and $Run.head_repository.id -eq $Policy.repositoryId) 'Historical first-attempt run changed.'
}

function Assert-RecoveryOutcomes($Outcome, $Policy) {
    Assert-Recovery ($Outcome.schemaVersion -eq 1 -and $Outcome.kind -ceq 'publication-outcomes' -and
        $Outcome.repository -ceq $Policy.repository -and $Outcome.sha -ceq $Policy.sha -and
        [string]$Outcome.publishRunId -ceq [string]$Policy.publicationRun -and [string]$Outcome.publishAttempt -ceq '1' -and
        $Outcome.loginOutcome -ceq 'success' -and $Outcome.pushOutcome -ceq 'failure' -and
        !$Outcome.authorizesRetry -and !$Outcome.remoteAcceptanceVerified -and @($Outcome.packages).Count -eq 2) 'Unexpected partial publication record.'
    $packages = $Outcome.packages
    Assert-Recovery ($packages[0].file -ceq 'AndreGoepel.Core.1.0.6.nupkg' -and $packages[0].sha256 -ceq $Policy.packageSha256 -and
        $packages[0].cliObservation -ceq 'cli-success' -and ($packages[0].events -join ',') -ceq 'started,cli-success' -and
        $packages[1].file -ceq 'AndreGoepel.Core.1.0.6.snupkg' -and $packages[1].sha256 -ceq $Policy.symbolsSha256 -and
        $packages[1].cliObservation -ceq 'uncertain' -and ($packages[1].events -join ',') -ceq 'started,uncertain-exit-1') 'The original per-file publication outcomes differ.'
}

function Read-RecoveryZip([string]$Path) {
    $archive = [IO.Compression.ZipFile]::OpenRead($Path)
    $files = [Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal)
    try {
        Assert-Recovery ($archive.Entries.Count -le 32) 'Unexpected archive inventory.'
        foreach ($entry in $archive.Entries) {
            Assert-Recovery ($entry.Length -le 5242880 -and !$files.ContainsKey($entry.FullName)) 'Duplicate or oversized archive entry.'
            if ($entry.FullName.EndsWith('/')) { continue }
            $stream = $entry.Open()
            $memory = [IO.MemoryStream]::new()
            try { $stream.CopyTo($memory); $files.Add($entry.FullName, $memory.ToArray()) }
            finally { $memory.Dispose(); $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
    return ,$files
}

function Assert-RecoveryPayload($Original, $Remote) {
    Assert-Recovery ($Remote.ContainsKey('.signature.p7s') -and $Remote.Count -eq $Original.Count + 1) 'Published package inventory/signature differs.'
    foreach ($entry in $Original.GetEnumerator()) {
        Assert-Recovery ($Remote.ContainsKey($entry.Key) -and
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($entry.Value)) -ceq
            [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Remote[$entry.Key]))) 'Published package payload differs from the approved original.'
    }
}

function Assert-RecoverySymbolsAbsent([int]$Status) {
    Assert-Recovery ($Status -eq 404) 'Symbols are already available or their absence cannot be established; do not upload.'
}

function Assert-RecoveryReceipt($Receipt, $Context, $Policy, [DateTimeOffset]$Now) {
    Assert-Recovery ($Receipt.schemaVersion -eq 1 -and $Receipt.recoveryRun -eq $Context.runId -and $Receipt.recoverySha -ceq $Context.sha -and
        $Receipt.releaseSha -ceq $Policy.sha -and $Receipt.file -ceq 'AndreGoepel.Core.1.0.6.snupkg' -and
        $Receipt.sha256 -ceq $Policy.symbolsSha256 -and $Receipt.remotePackageVerified -and $Receipt.symbolsAbsent -and
        !$Receipt.authorizesRetry -and [DateTimeOffset]$Receipt.verifiedAt -le $Now -and
        [DateTimeOffset]$Receipt.verifiedAt -ge $Now.AddMinutes(-2) -and [DateTimeOffset]$Receipt.readinessExpiresAt -gt $Now) 'Recovery verification is missing, changed or stale.'
}

function Get-RecoveryObservation([string]$Login, [string]$Push, [string]$Marker) {
    Assert-Recovery ($Login -in @('success','failure','cancelled','skipped') -and $Push -in @('success','failure','cancelled','skipped')) 'Invalid recovery step outcomes.'
    if ($Marker -eq '') {
        Assert-Recovery ($Push -ne 'success') 'Successful push has no dispatch record.'
        return 'not-dispatched'
    }
    Assert-Recovery ($Login -ceq 'success' -and $Push -ne 'skipped' -and $Marker -in @('started','cli-success')) 'Recovery dispatch contradicts step outcomes.'
    if ($Marker -ceq 'cli-success') { return 'cli-success' }
    Assert-Recovery ($Push -ne 'success') 'Successful push has no CLI completion record.'
    return 'uncertain'
}
