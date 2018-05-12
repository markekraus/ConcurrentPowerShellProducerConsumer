Clear-Host

# Install Module
$ModuleName = "ThreadJob"
$installModuleSplat = @{
    SkipPublisherCheck = $true
    AcceptLicense = $true
    Name = $ModuleName
    Force = $true
    Scope = 'CurrentUser'
    AllowClobber = $true
    WarningAction = 'SilentlyContinue'
}
Install-Module @installModuleSplat

# Start Jobs
$Jobs = @(
    Start-ThreadJob { 
        start-sleep -Seconds 1
        Get-Date
    }
    Start-ThreadJob { 
        start-sleep -Seconds 2
        Get-Date
    }
)

# Return Results
@"


Results:
"@
$Jobs |
    Receive-Job -Wait

# Cleanup
$Jobs | Remove-Job
@"


"@