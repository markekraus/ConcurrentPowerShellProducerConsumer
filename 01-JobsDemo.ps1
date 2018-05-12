Clear-Host

# Start Jobs
$Jobs = @(
    Start-Job { 
        start-sleep -Seconds 1
        Get-Date
    }
    Start-Job { 
        start-sleep -Seconds 2
        Get-Date
    }
)

# Return Jobs
@"


Results:
"@
$Jobs |
    Receive-Job -Wait

# Cleanup
$Jobs | Remove-Job
@"


"@
