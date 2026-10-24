param([Parameter(Mandatory)][string]$PackageDirectory)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$workflow = (Get-Content -Raw (Join-Path $repo '.github/workflows/nuget-publish.yml')).Replace("`r`n","`n")
$regular = [regex]::Match($workflow,'(?ms)^            arguments=\(nuget push.*?^            esac$')
$recovery = [regex]::Match($workflow,'(?m)dotnet nuget push "\$package" --source https://api.nuget.org/v3/index.json \\\n            --configfile "\$root/NuGet.Config" --timeout 300')
if (!$regular.Success -or !$recovery.Success) { throw 'Publisher command blocks not found.' }
$package = @(Get-ChildItem -LiteralPath $PackageDirectory -Filter '*.nupkg')
$symbols = @(Get-ChildItem -LiteralPath $PackageDirectory -Filter '*.snupkg')
if ($package.Count -ne 1 -or $symbols.Count -ne 1) { throw 'Provide exactly one already-built package and its symbol archive.' }
$folder = Join-Path $repo ('artifacts/sonar/symbol-routing-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $folder | Out-Null
'<configuration />' | Set-Content -NoNewline -Encoding utf8NoBOM (Join-Path $folder 'NuGet.Config')
$bash = if ($IsWindows) { 'C:/Program Files/Git/bin/bash.exe' } else { 'bash' }
$setup = @'
set -euo pipefail
package=$1
PUBLISH_ROOT=$2
root=$2
file=$(basename -- "$package")
'@
$ordinaryScript = $setup + "`n" + ($regular.Value -replace '(?m)^            ','') + "`n" + 'printf ''%s\n'' "${arguments[@]}"'
$recoveryScript = $setup + "`n" + 'dotnet() { printf ''%s\n'' "$@"; }' + "`n" + $recovery.Value
[IO.File]::WriteAllText((Join-Path $folder 'ordinary.sh'),$ordinaryScript,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $folder 'recovery.sh'),$recoveryScript,[Text.UTF8Encoding]::new($false))

function Invoke-Isolated([string]$Command,[string[]]$Arguments) {
    $start=[Diagnostics.ProcessStartInfo]::new($Command)
    $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.WorkingDirectory=$repo
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    foreach ($name in @($start.Environment.Keys)) {
        if ($name -match '^(NUGET_|WORKFLOWS_|ACTIONS_ID_TOKEN_|GH_|GITHUB_)') { [void]$start.Environment.Remove($name) }
    }
    foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
    $process=[Diagnostics.Process]::Start($start)
    $outTask=$process.StandardOutput.ReadToEndAsync(); $errTask=$process.StandardError.ReadToEndAsync()
    if (!$process.WaitForExit(30000)) { $process.Kill($true); throw 'Loopback CLI test timed out.' }
    $result=[pscustomobject]@{exitCode=$process.ExitCode;stdout=$outTask.Result;stderr=$errTask.Result}
    $process.Dispose()
    return $result
}

$portProbe=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
$portProbe.Start(); $port=$portProbe.LocalEndpoint.Port; $portProbe.Stop()
$base="http://127.0.0.1:$port/"
$requestsPath=Join-Path $folder 'requests.jsonl'
$server=Start-Job -ArgumentList $base,$requestsPath -ScriptBlock {
    param($base,$requestsPath)
    $ErrorActionPreference='Stop'
    $listener=[Net.HttpListener]::new(); $listener.Prefixes.Add($base); $listener.Start()
    'READY'
    try {
        while ($listener.IsListening) {
            $context=$listener.GetContext(); $request=$context.Request
            $path=$request.Url.AbsolutePath.TrimEnd('/')
            if ($path -eq '/stop') { $context.Response.StatusCode=200; $context.Response.Close(); break }
            if ($path -eq '/v3/index.json' -and $request.HttpMethod -eq 'GET') {
                $body=@{version='3.0.0';resources=@(@{'@id'="${base}api/v2/package";'@type'='PackagePublish/2.0.0'},@{'@id'="${base}api/v2/symbolpackage";'@type'='SymbolPackagePublish/4.9.0'})} | ConvertTo-Json -Depth 5 -Compress
                $bytes=[Text.Encoding]::UTF8.GetBytes($body)
                $context.Response.StatusCode=200; $context.Response.ContentType='application/json'
                $context.Response.OutputStream.Write($bytes)
            } elseif ($request.HttpMethod -eq 'PUT' -and $path -in @('/api/v2/package','/api/v2/symbolpackage')) {
                $memory=[IO.MemoryStream]::new()
                try { $request.InputStream.CopyTo($memory); $bodyBytes=$memory.ToArray() } finally { $memory.Dispose() }
                $text=[Text.Encoding]::ASCII.GetString($bodyBytes)
                $start=$text.IndexOf("`r`n`r`n")+4; $end=$text.LastIndexOf("`r`n--")
                if ($start -lt 4 -or $end -le $start) { throw 'Unexpected NuGet multipart request.' }
                $payload=[byte[]]$bodyBytes[$start..($end-1)]
                @{path=$path;sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($payload)).ToLowerInvariant();credentialPresent=([bool]$request.Headers['X-NuGet-ApiKey'])} | ConvertTo-Json -Compress | Add-Content $requestsPath
                $context.Response.StatusCode=201
            } else { $context.Response.StatusCode=404 }
            $context.Response.Close()
        }
    } finally { $listener.Close() }
}
try {
    $ready=$false
    for ($i=0;$i -lt 50;$i++) {
        if (@(Receive-Job $server -Keep) -contains 'READY') { $ready=$true; break }
        Start-Sleep -Milliseconds 100
    }
    if (!$ready) { throw 'Loopback mock failed to start.' }
    $results=@()
    foreach ($mode in @('ordinary-package','ordinary-symbols','legacy-symbols','recovery-symbols')) {
        # Arrange
        $file=if ($mode -eq 'ordinary-package') { $package[0].FullName } else { $symbols[0].FullName }
        $script=if ($mode -eq 'recovery-symbols') { 'recovery.sh' } else { 'ordinary.sh' }
        $capture=Invoke-Isolated $bash @((Join-Path $folder $script).Replace('\','/'),$file.Replace('\','/'),$folder.Replace('\','/'))
        if ($capture.exitCode -ne 0) { throw $capture.stderr }
        $arguments=@($capture.stdout.TrimEnd() -split '\r?\n')
        $source=[Array]::IndexOf($arguments,'--source')
        if ($source -lt 0 -or $arguments[$source+1] -cne 'https://api.nuget.org/v3/index.json') { throw 'Actual publisher uses an unexpected feed.' }
        if ($arguments -contains '--skip-duplicate' -or $arguments -contains '--symbol-source') { throw 'Actual publisher contains bypass or legacy symbol arguments.' }
        $arguments[$source+1]="${base}v3/index.json"
        $arguments[[Array]::IndexOf($arguments,'--timeout')+1]='15'
        $arguments+=@('--allow-insecure-connections')
        if ($mode -eq 'legacy-symbols') { $arguments+=@('--symbol-source',"${base}api/v2/symbolpackage",'--no-service-endpoint') }

        # Act
        $result=Invoke-Isolated 'dotnet' $arguments

        # Assert
        $result | ConvertTo-Json | Set-Content (Join-Path $folder "$mode.json")
        if ($mode -eq 'legacy-symbols') {
            if ($result.exitCode -eq 0 -or ($result.stdout+$result.stderr) -notmatch 'File does not exist') { throw 'The original defect was not reproduced.' }
        } elseif ($result.exitCode -ne 0) { throw "Actual $mode invocation failed: $($result.stdout)$($result.stderr)" }
        $results+=@{mode=$mode;exitCode=$result.exitCode}
    }

    # Assert
    $requests=@(Get-Content $requestsPath | ForEach-Object { $_ | ConvertFrom-Json })
    if ($requests.Count -ne 3 -or ($requests.path -join ',') -cne '/api/v2/package,/api/v2/symbolpackage,/api/v2/symbolpackage' -or
        @($requests | Where-Object credentialPresent).Count -ne 0 -or
        $requests[0].sha256 -cne (Get-FileHash $package[0].FullName).Hash.ToLowerInvariant() -or
        $requests[1].sha256 -cne (Get-FileHash $symbols[0].FullName).Hash.ToLowerInvariant() -or $requests[1].sha256 -cne $requests[2].sha256) {
        throw 'Wrong endpoint, implicit symbol dispatch, credentials or changed bytes reached the loopback mock.'
    }
    [ordered]@{cases=$results;requests=$requests;externalUpload=$false;credentialsUsed=$false} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $folder 'result.json')
    Write-Output "PASS four actual CLI routing cases and exact request payload hashes. Evidence: $folder"
} finally {
    try { Invoke-WebRequest "${base}stop" -TimeoutSec 5 -SkipHttpErrorCheck | Out-Null } catch { }
    Wait-Job $server -Timeout 5 | Out-Null
    Stop-Job $server
    Remove-Job $server
}
