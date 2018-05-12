Clear-Host

# Install Module
$ModuleName = "PoshRSJob"
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

# Run Jobs
$Jobs = 1..5 | Start-RSJob -ScriptBlock {
    'Running Job {0} at {1}' -f $_, (Get-Date)
} 

# Return Jobs
@"


Results:
"@
$Jobs | 
    Wait-RSJob  |
    Receive-RSJob 

# Cleanup
$Jobs | Remove-RSJob
@"


"@
