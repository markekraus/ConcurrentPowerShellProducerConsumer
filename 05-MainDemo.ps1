Clear-Host

# Settings
$Folders = @(
    'c:\ConcurrentDemo\Folder1'
    'c:\ConcurrentDemo\Folder2'
    'c:\ConcurrentDemo\Folder3'
    'c:\ConcurrentDemo\Folder4'
    'c:\ConcurrentDemo\Folder5'
    'c:\ConcurrentDemo\Folder6'
    'c:\ConcurrentDemo\Folder7'
)
$LogPath = 'c:\ConcurrentDemo\Log.txt'

# Modify these to change the number of each type of worker
$FileProducersCount = 3
$FileConsumersCount = 5
$LogConsumersCount = 1



# Create Files
$RandomFileRange = 20,50
Remove-Item -Recurse -Path 'c:\ConcurrentDemo\' -Force -ErrorAction SilentlyContinue
$Null = foreach ($Folder in $Folders) {
    New-Item -ItemType Directory $Folder -ErrorAction SilentlyContinue 
    $Files = Get-Random -Minimum $RandomFileRange[0] -Maximum $RandomFileRange[1]
    0..$Files | ForEach-Object {
        $FileName = '{0}.txt' -f (New-Guid)
        New-Item -Path $Folder -Name $FileName -ItemType File
    }
}

# This ScriptBlock Produces a list of file names
$FileProducer = {
    param(
        [System.Collections.Concurrent.BlockingCollection[PSObject]]
        $FolderQueue,

        [System.Collections.Concurrent.BlockingCollection[PSObject]]
        $FileNameQueue,

        [System.Collections.Concurrent.BlockingCollection[PSObject]]
        $LogQueue,

        [System.Collections.Concurrent.BlockingCollection[int]]
        $FileProducerStack,

        [String]
        $ThreadName
    )

    # Add this thread to the stack
    $FileProducerStack.Add(
        [System.Threading.Thread]::CurrentThread.ManagedThreadId
    )

    # Loop through each folder in the queue
    foreach ($FolderPath in $FolderQueue.GetConsumingEnumerable()) {
        # Loop through each file in the folder
        foreach ($Item in (Get-ChildItem $FolderPath)) {
            # Add the filename to File Name queue
            $FileNameQueue.Add($Item.Name)
            # Add a Log entry to the log queue
            $LogQueue.Add([PSCustomObject]@{
                Date = Get-Date
                ThreadName = $ThreadName
                ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
                Message = 'Found {0}' -f $Item.Name
            })
        }
    }

    # Remove a thread from the stack
    $null = $FileProducerStack.Take()

    # Close  $FileNameQueue if this is the last thread
    if($FileProducerStack.Count -lt 1) {
        $FileProducerStack.CompleteAdding()
        $FileNameQueue.CompleteAdding()
    }
}

# This ScriptBlock Reverse the file names
$FileConsumer = {
    param(
        [System.Collections.Concurrent.BlockingCollection[PSObject]]
        $FileNameQueue,

        [System.Collections.Concurrent.BlockingCollection[PSObject]]
        $LogQueue,

        [System.Collections.Concurrent.BlockingCollection[int]]
        $FileConsumerStack,

        [String]
        $ThreadName
    )

    # Add this thread to the stack
    $FileConsumerStack.Add(
        [System.Threading.Thread]::CurrentThread.ManagedThreadId
    )

    # Loop through each filename
    foreach ($Filename in $FileNameQueue.GetConsumingEnumerable()) {
        # Reverse the file name
        $Chars = $FileName.ToCharArray()
        [Array]::Reverse($Chars)
        $Reversed = -join $Chars
        # Add message to the log queue
        $LogQueue.Add([PSCustomObject]@{
            Date = Get-Date
            ThreadName = $ThreadName
            ThreadId = [System.Threading.Thread]::CurrentThread.ManagedThreadId
            Message = ("Old Name: '{0}'; New Name '{1}'" -f $Filename, $Reversed)
        })
    }

    # Remove a thread from the stack
    $null = $FileConsumerStack.Take()

    # Close LogQueue if this is the last thread
    if($FileConsumerStack.Count -lt 1) {
        $FileConsumerStack.CompleteAdding()
        $LogQueue.CompleteAdding()
    }
}

# This ScriptBlock Logs Events from the other threads
$LogConsumer = {
    param(
        [String]
        $LogPath,

        [System.Collections.Concurrent.BlockingCollection[PSObject]]
        $LogQueue,

        [String]
        $ThreadName
    )

    # Log Start
    $Message = '{0} - {1:00000} - {2:-15} - {3}' -f @(
        (Get-Date).ToString('o')
        [System.Threading.Thread]::CurrentThread.ManagedThreadId
        $ThreadName
        'Logging Start'
    )
    $Message | Add-Content -Path $LogPath
    [console]::WriteLine($Message)

    # loop through the Log Queue and add the messages ot the log
    foreach ($LogEntry in $LogQueue.GetConsumingEnumerable()) {
        $Message = '{0} - {1:00000} - {2:-15} - {3}' -f @(
            $LogEntry.Date.ToString('o')
            $LogEntry.ThreadId
            $LogEntry.ThreadName
            $LogEntry.Message 
        )
        $Message | Add-Content -Path $LogPath
        [console]::WriteLine($Message)
    }

    $LogEnd
    $Message = '{0} - {1:00000} - {2:-15} - {3}' -f @(
        (Get-Date).ToString('o')
        [System.Threading.Thread]::CurrentThread.ManagedThreadId
        $ThreadName
        'Logging Complete'
    )
    $Message | Add-Content -Path $LogPath
    [console]::WriteLine($Message)
}


# Create the Queues and Stacks used
# Queue for folder paths
$FolderQueue = [System.Collections.Concurrent.BlockingCollection[PSObject]]::new(
    [System.Collections.Concurrent.ConcurrentQueue[PSObject]]::new()
)
# Queue for File Names
$FileNameQueue = [System.Collections.Concurrent.BlockingCollection[PSObject]]::new(
    [System.Collections.Concurrent.ConcurrentQueue[PSObject]]::new()
)
# Queue for Log messages
$LogQueue = [System.Collections.Concurrent.BlockingCollection[PSObject]]::new(
    [System.Collections.Concurrent.ConcurrentQueue[PSObject]]::new()
)
# Stack for FileProducer Threads
$FileProducerStack = [System.Collections.Concurrent.BlockingCollection[int]]::new(
    [System.Collections.Concurrent.ConcurrentStack[int]]::new()
)
# Stack for FileConsumer Threads
$FileConsumerStack = [System.Collections.Concurrent.BlockingCollection[int]]::new(
    [System.Collections.Concurrent.ConcurrentStack[int]]::new()
)

# Create a list to hold the Runspaces
$Runspaces = [System.Collections.Generic.List[PSObject]]::New()

# Create the File Producer Pool
$FileProducerPool = [RunspaceFactory]::CreateRunspacePool(1,$FileProducersCount)
$FileProducerPool.Open()
# Create the File Producer Runspaces
1..$FileProducersCount | ForEach-Object {
    $ThreadName = 'FileProducer{0:00}' -f $_
    $Runspace = [PowerShell]::Create()
    $Runspace.RunspacePool = $FileProducerPool
    $null = $Runspace.AddScript($FileProducer).
        AddArgument($FolderQueue).
        AddArgument($FileNameQueue).
        AddArgument($LogQueue).
        AddArgument($FileProducerStack).
        AddArgument($ThreadName)
    $Runspaces.Add([PSCustomObject]@{
        Name = $ThreadName
        PowerShell = $Runspace
        Handler = $Runspace.BeginInvoke()
    })
}

# Create the File Consumer Pool
$FileConsumerPool = [runspacefactory]::CreateRunspacePool(1,$FileConsumersCount)
$FileConsumerPool.Open()
# Create the File Consumer Runspaces
1..$FileConsumersCount | ForEach-Object {
    $ThreadName = 'FileConsumer{0:00}' -f $_
    $Runspace = [PowerShell]::Create()
    $Runspace.RunspacePool = $FileConsumerPool
    $null = $Runspace.AddScript($FileConsumer).
        AddArgument($FileNameQueue).
        AddArgument($LogQueue).
        AddArgument($FileConsumerStack).
        AddArgument($ThreadName)
    $Runspaces.Add([PSCustomObject]@{
        Name = $ThreadName
        PowerShell = $Runspace
        Handler = $Runspace.BeginInvoke()
    })
}

# create the Log Consumer Pool
$LogConsumerPool = [runspacefactory]::CreateRunspacePool(1,$LogConsumersCount)
$LogConsumerPool.Open()
# Create the Log Consumer Runspaces
1..$LogConsumersCount | ForEach-Object {
    $ThreadName = 'LogConsumer{0:00}' -f $_
    $Runspace = [PowerShell]::Create()
    $Runspace.RunspacePool = $LogConsumerPool
    $null = $Runspace.AddScript($LogConsumer).
        AddArgument($LogPath).
        AddArgument($LogQueue).
        AddArgument($ThreadName)
    $Runspaces.Add([PSCustomObject]@{
        Name = $ThreadName
        PowerShell = $Runspace
        Handler = $Runspace.BeginInvoke()
    })
}

# At this point, All runspaces are running but doing nothing. 
# Now we feed the list of folder paths to the Folder queue
$null = $Folders | ForEach-Object { $FolderQueue.Add($_)}
$null = $FolderQueue.CompleteAdding()

# Wait for the threads to complete
while ($Runspaces.Handler.IsCompleted -contains $false) {
    Start-Sleep -Milliseconds 500
}

# Cleanup
Foreach($Runspace in $Runspaces) {
    $Runspace.PowerShell.EndInvoke($Runspace.Handler)
    $Runspace.PowerShell.Dispose()
}
$FileProducerPool.Dispose()
$FileConsumerPool.Dispose()
$LogConsumerPool.Dispose()

# View the log
Invoke-Item $LogPath
