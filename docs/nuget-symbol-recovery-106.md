# Core 1.0.6: completed symbol recovery

The separately authorized symbol-only recovery completed on October 24, 2026.
The original package, symbol archive and exact DLL-bound PDB were independently
verified on NuGet, completing [#29](https://github.com/andregoepel/core/issues/29).
This historical report preserves the result and the lookup defect found during
acceptance. [#39](https://github.com/andregoepel/core/issues/39) removes the spent
manual recovery path; this document is not an instruction to upload again.

## Incident and ordinary publisher correction

The immutable release [v1.0.6](https://github.com/andregoepel/core/releases/tag/v1.0.6)
points to `06e816a983d27e4d215042acc47e63f1ddba2075`. Preparation
[40100316402](https://github.com/andregoepel/core/actions/runs/40100316402), attempt 1,
succeeded. Publication
[40100437520](https://github.com/andregoepel/core/actions/runs/40100437520), attempt 1,
verified the handoff, preserved intent, obtained temporary NuGet credentials and
uploaded the main package with HTTP 201. Its symbol command then failed locally
with `File does not exist`. The intent and per-file outcomes were retained.

The explicit V2 `--symbol-source` override bypassed V3 symbol-resource discovery
and caused SDK 10.0.402 to look for a legacy `.symbols.nupkg` file. The correction
in [PR #38](https://github.com/andregoepel/core/pull/38) uses only the NuGet V3 index
as the source. The ordinary `.nupkg` command retains `--no-symbols`, so each
verified file is dispatched separately. This follows
[NuGet's symbol publishing instructions](https://learn.microsoft.com/nuget/create-packages/symbol-packages-snupkg)
and [SymbolPackagePublish discovery](https://learn.microsoft.com/nuget/api/symbol-package-publish-resource).

## Completed recovery and retained evidence

The authorized recovery ran on `065b6564d4073e7a2e70aef00ff8f83d60fb2520` in
[40105324520](https://github.com/andregoepel/core/actions/runs/40105324520), attempt 1.
It authenticated the original preparation/publication artifacts, compared the
signed public package with its original payload, and checked fresh current-main
CI and Sonar readiness. Protected approval, stored intent and repeated verification
preceded official `NuGet/login` and the symbol-only native push.

Exactly one symbol upload received HTTP 201 at 15:07:31 UTC. All ordinary
publication steps were skipped; the original main package was not uploaded again.
There was no release/tag change or rebuilt replacement package. The recovery
variable was removed afterward. The original first-attempt guard was spent.

The retained recovery intent artifact is `12563969586`, with SHA-256
`403bcdc35c56c633c30724240b5b3126c34a8e963d1c557c625b6732256bddc5`;
the outcome artifact is `12564527493`. Their configured retention is 90 days.
Authenticated copies of the original preparation artifacts, remote package and
symbol checks, logs and acceptance records are also retained locally outside Git.
Removing recovery code does not delete this evidence. External evidence storage
remains deferred; GitHub retention is finite.

Independent verification completed at 15:18:10 UTC. The public signed package's
six payload entries match the approved original; NuGet's repository signature is
the additional entry. The public symbol archive and PDB match the original bytes:

| Artifact | SHA-256 |
| --- | --- |
| Original unsigned `.nupkg` | `7bfb454800f52ffebef660a64648a62396896df69e1df697d721176e60acbb74` |
| Public signed `.nupkg` | `c07de56345db2bafadc0eeeb78348d4b6c18b7f556a07b35163cd353e8986b35` |
| Original and public `.snupkg` | `f10463edb103b64f6d27f67efb948ccf3731136d472742d0b8eee4c5878d53dc` |
| Original and public portable PDB | `20c2fd9d3c1f012195ab056eeabf39d61d33f693b8a7f53a212f9112a1ae7673` |

## PDB lookup defect and future verification

The removed recovery script constructed its PDB URL using mixed-case file names
and an uppercase GUID. After upload, that URL still returned HTTP 404 while the
canonical key returned HTTP 200 at the same check. This was a casing defect, not
continued indexing delay. **A 404 from that incorrect URL did not prove symbol
absence and must not be used to authorize another upload.** Ordinary publication
does not use that probe.

Microsoft's official `dotnet-symbol` 10.0.750501 derived this key from the
published DLL and validated its embedded checksum:

```text
andregoepel.core.pdb/d267506612b942e18fc7f56cf0cff837FFFFFFFF/andregoepel.core.pdb
```

The file names and GUID are lowercase; the portable-PDB suffix `FFFFFFFF` is
uppercase, as specified by
[Microsoft's symbol key conventions](https://github.com/dotnet/symstore/blob/main/docs/specs/SSQP_Key_Conventions.md#portable-pdb-signature).
The downloaded PDB matched the original SHA-256 above. An independent canonical-URL
GET returned the same bytes. The DLL's embedded PDB checksum was
`665067d2b912e1320fc7f56cf0cff83724f096b0ea089d01124c26ce9718a1da`;
that embedded checksum is distinct from the PDB file's SHA-256.

For future read-only symbol verification, prefer the
[official symbol client](https://learn.microsoft.com/dotnet/core/diagnostics/dotnet-symbol)
against the DLL extracted from the published package. Use a fresh cache and
output directory, inspect the resolved server/key and checksum validation, and
compare the downloaded PDB with the authenticated original. For example:

```text
dotnet-symbol --server-path https://symbols.nuget.org/download/symbols --symbols --diagnostics --cache-directory <fresh-cache> --output <fresh-output> <published-dll>
```

A failed lookup alone does not authorize retrying publication. Reconcile the
retained upload outcomes and remote package/symbol state under a separately
reviewed recovery plan. No permanent recovery dispatcher or custom uploader is
retained by this cleanup.

## Remaining publisher and regression checks

`nuget-publish.yml` accepts only successful production preparation completions.
The 1.0.6 manual input, variable guard, recovery steps, scripts, pins and
recovery-only tests are removed. Ordinary evidence, replay, protected approval,
intent, per-file verification, outcome retention and cleanup checks remain intact.
Preparation, CI, Sonar, their policies and other workflows are unchanged.

The next ordinary release must use a subsequent reviewed commit. The shared
verifier's one-publisher-run-per-SHA rule deliberately rejects publication on
recovery SHA `065b6564d4073e7a2e70aef00ff8f83d60fb2520`; do not relax that guard.
Merging the cleanup does not create or authorize a release.

Run the existing outcome recorder and tagged-handoff tests, plus:

```text
pwsh -NoProfile -File scripts/sonar/publication/tests/symbol-routing.ps1 -PackageDirectory <directory-containing-one-nupkg-and-snupkg>
```

With SDK 10.0.402 and Bash installed, the routing test extracts the actual ordinary
publisher arguments and invokes the real NuGet CLI against a loopback V3 index.
Three cases verify package-only routing, symbol routing and reproduction of the
legacy-override failure. The mock requires exactly two PUTs, checks each endpoint
and payload hash, and rejects credentials. No requests go to NuGet. Linux tests
can run with container networking disabled; only loopback is required.
