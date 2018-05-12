Clear-Host

# Build RunspacePool
$RunspacePool = [runspacefactory]::CreateRunspacePool(1,4)
$RunspacePool.Open()

# Build Runspaces
$Runspaces = 1..2 | ForEach-Object {
    $Runspace = [PowerShell]::Create()
    $Runspace.RunspacePool = $RunspacePool
    $Null = $Runspace.AddScript({
        param($Count)
        Start-Sleep -Seconds $Count
        'Running job {0} at {1}' -f $Count, (Get-Date)
    }).AddArgument($_)
    $Handler = $Runspace.BeginInvoke()
    [PSCustomObject]@{
        Count = $_
        PowerShell = $Runspace
        Handler = $Handler
    }
}

while ($Runspaces.Handler.IsCompleted -contains $false) {
    Start-Sleep -Milliseconds 500
}

# Get results and cleanup
@"


Results:
"@
Foreach($Runspace in $Runspaces) {
    $Runspace.PowerShell.EndInvoke($Runspace.Handler)
    $Runspace.PowerShell.Dispose()
}
$RunspacePool.Dispose()
@"


"@
