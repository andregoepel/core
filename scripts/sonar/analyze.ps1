[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ServerId,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9]+(?:-[a-z0-9]+)*$')][string]$RunName,
    [string]$Url = 'http://127.0.0.1:9000',
    [ValidatePattern('^core-local(?:-[a-z0-9]+)*$')][string]$Project = 'core-local'
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$policy = Get-Content (Join-Path $PSScriptRoot 'main-policy.json') -Raw | ConvertFrom-Json
$revision = $policy.toolRevision
if ($revision -notmatch '^[0-9a-f]{40}$') { throw 'Review and pin the shared runner first.' }
if ($ServerId -eq $policy.serverId) { throw 'Local verification cannot use the central server.' }
$target = [Uri]$Url
if ($target.Scheme -ne 'http' -or $target.Host -notin @('localhost', '127.0.0.1', '[::1]') -or $target.Port -ne 9000 -or $target.AbsolutePath -ne '/' -or $target.UserInfo -or $target.Query -or $target.Fragment) {
    throw 'Use the separate loopback Sonar prototype on port 9000.'
}

# A fresh immutable checkout avoids trusting previously modified cached tooling.
$bootstrapRoot = Join-Path $root 'artifacts/sonar-bootstrap'
$bootstrap = Join-Path $bootstrapRoot ([Guid]::NewGuid().ToString('N'))
$scanToken = $env:WORKFLOWS_SONAR_TOKEN
$verifyToken = $env:WORKFLOWS_SONAR_VERIFY_TOKEN
$githubToken = $env:WORKFLOWS_GITHUB_TOKEN
$exitCode = 1
try {
    $env:WORKFLOWS_SONAR_TOKEN = $null
    $env:WORKFLOWS_SONAR_VERIFY_TOKEN = $null
    $env:WORKFLOWS_GITHUB_TOKEN = $null
    New-Item -ItemType Directory -Path $bootstrap -Force | Out-Null
    git -C $bootstrap init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the shared runner checkout.' }
    git -C $bootstrap fetch --quiet --depth 1 https://github.com/andregoepel/workflows.git $revision
    if ($LASTEXITCODE -ne 0) { throw 'Could not fetch the pinned shared runner.' }
    git -C $bootstrap checkout --quiet --detach FETCH_HEAD
    if ($LASTEXITCODE -ne 0 -or (git -C $bootstrap rev-parse HEAD).Trim() -ne $revision) { throw 'Unexpected shared runner revision.' }

    Push-Location (Join-Path $bootstrap 'sonar')
    try {
        $toolProject = 'src/AndreGoepel.Workflows.Sonar/AndreGoepel.Workflows.Sonar.csproj'
        dotnet restore $toolProject --locked-mode
        if ($LASTEXITCODE -ne 0) { throw 'Shared runner restore failed.' }
        dotnet publish $toolProject -c Release --no-restore --no-self-contained -o (Join-Path $bootstrap 'runner')
        if ($LASTEXITCODE -ne 0) { throw 'Shared runner build failed.' }
    } finally {
        Pop-Location
    }

    $env:WORKFLOWS_SONAR_TOKEN = $scanToken
    $env:WORKFLOWS_SONAR_VERIFY_TOKEN = $verifyToken
    dotnet (Join-Path $bootstrap 'runner/AndreGoepel.Workflows.Sonar.dll') --root $root --url $Url --project $Project --server-id $ServerId --run-name $RunName
    $exitCode = $LASTEXITCODE
} finally {
    $env:WORKFLOWS_SONAR_TOKEN = $scanToken
    $env:WORKFLOWS_SONAR_VERIFY_TOKEN = $verifyToken
    $env:WORKFLOWS_GITHUB_TOKEN = $githubToken
    $resolved = [IO.Path]::GetFullPath($bootstrap)
    if ((Test-Path -LiteralPath $resolved) -and [IO.Path]::GetDirectoryName($resolved) -eq [IO.Path]::GetFullPath($bootstrapRoot)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
exit $exitCode
