param(
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$WorkDirectory,
    [Parameter(Mandatory=$true)][ValidateRange(1,120)][int]$TimeoutSeconds
)
$ErrorActionPreference = 'Stop'
$encoding = New-Object System.Text.UTF8Encoding($false)
$process = New-Object System.Diagnostics.Process
$status = 125
$started = $false
try {
    $argumentsPath = [IO.Path]::Combine($WorkDirectory, 'arguments.txt')
    # The upstream launcher uses ANSI paths for its DLL lookup. Reuse existing 8.3 names; never relocate the payload.
    if ($Executable -match '[^\x00-\x7F]' -or $argumentsPath -match '[^\x00-\x7F]') {
        $fileSystem = New-Object -ComObject Scripting.FileSystemObject
        if ($Executable -match '[^\x00-\x7F]') { $Executable = $fileSystem.GetFile($Executable).ShortPath }
        if ($argumentsPath -match '[^\x00-\x7F]') { $argumentsPath = $fileSystem.GetFile($argumentsPath).ShortPath }
        if ($Executable -match '[^\x00-\x7F]' -or $argumentsPath -match '[^\x00-\x7F]') {
            throw 'ExifTool requires an ASCII installation and work path when Windows 8.3 names are unavailable. Move the plugin to an ASCII-only path.'
        }
    }
    if ($argumentsPath.Contains('"')) { throw 'Invalid argument file path' }
    $process.StartInfo.FileName = $Executable
    $process.StartInfo.Arguments = '-config "" -charset filename=UTF8 -@ "' + $argumentsPath + '"'
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = $encoding
    $process.StartInfo.StandardErrorEncoding = $encoding
    $started = $process.Start()
    if (-not $started) { throw 'Could not start ExifTool' }
    # Drain both streams concurrently so WaitForExit cannot deadlock on a full pipe.
    $outputTask = $process.StandardOutput.ReadToEndAsync()
    $errorTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        [IO.File]::WriteAllText([IO.Path]::Combine($WorkDirectory, 'timed-out.txt'), 'timeout', $encoding)
        & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null
        if (-not $process.WaitForExit(2000)) { throw 'ExifTool did not stop after timeout' }
        $status = 124
    } else {
        $status = $process.ExitCode
    }
    if (-not $outputTask.Wait(2000) -or -not $errorTask.Wait(2000)) {
        throw 'ExifTool output streams did not close'
    }
    [IO.File]::WriteAllText([IO.Path]::Combine($WorkDirectory, 'stdout.json'), $outputTask.Result, $encoding)
    [IO.File]::WriteAllText([IO.Path]::Combine($WorkDirectory, 'stderr.txt'), $errorTask.Result, $encoding)
} catch {
    $status = 125
    if ($started -and -not $process.HasExited) {
        & "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Null
        if (-not $process.WaitForExit(2000)) {
            [IO.File]::WriteAllText([IO.Path]::Combine($WorkDirectory, 'process-running.txt'), 'not stopped', $encoding)
        }
    }
    [IO.File]::WriteAllText([IO.Path]::Combine($WorkDirectory, 'stderr.txt'), $_.Exception.Message, $encoding)
} finally {
    $process.Dispose()
    [IO.File]::WriteAllText([IO.Path]::Combine($WorkDirectory, 'exit-code.txt'), [string]$status, $encoding)
}
exit $status
