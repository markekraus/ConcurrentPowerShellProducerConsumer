# Concurrent Programming in PowerShell with the Producer Consumer Pattern

## What is Concurrent Computing?

> Concurrent computing is a form of computing in which several computations are executed during overlapping time periods—concurrently—instead of sequentially (one completing before the next starts). ([Wikipedia](https://en.wikipedia.org/wiki/Concurrent_computing))

## Serial vs Concurrent vs Parallel

### Serial

* Tasks complete one after the other
* Tasks never run at the same time
* Uses a single thread
* Slowest

```none
Task 1: +
Task 2: =

Core 1: +++++++++++++++++++++++++++===========================
```

### Parallel

* Uses one core per task
* Not possible on single core system
* Faster but more expensive

```none
Task 1: +
Task 2: =

Core 1:   +++++++++++++++++++++++++++
Thread 1: +++++++++++++++++++++++++++

Core 2:   ===========================
Thread 1: ===========================
```

### Concurrent

* Uses multiple threads
* Can run on single core
* Slower but cheaper

```none
Task 1: +
Task 2: =

Core 1:   +++===++++++======+++===++++++======+++++++++=========
Thread 1: +++++++++++++++++++++++++++
Thread 2: ===========================
```

## PowerShell Concurrency Options

A quick recap of the available concurrent programming methods in PowerShell.

* PowerShell Jobs
* PoshRSJob
* PSThreadJob
* Runspaces

### PowerShell Jobs

* Native to PowerShell
* Seperate Process
* `Start-Job` and friends

[Jobs Demo](./01-JobsDemo.ps1)

### PoshRSJob

* Community module by Boe Prox
* [https://github.com/proxb/PoshRSJob](https://github.com/proxb/PoshRSJob)
* Abstracts PowerShell Runspaces

[PoshRSJob Demo](./02-PoshRSJobDemo.ps1)

### PSThreadJob

* PowerShell Team Module by Paul Higinbotham
* [https://github.com/PaulHigin/PSThreadJob](https://github.com/PaulHigin/PSThreadJob)
* Abstract PowerShell Runspaces
* Uses built-in Job cmdlets for management

[PSThreadJob Demo](./03-PSThreadJobDemo.ps1)

### Runspaces

* Built-in PowerShell API
* Raw .NET calls

[Runspace Demo](./04-RunspaceDemo.ps1)

## Producer-Consumer Pattern

### What is the Produce-Consumer Pattern?

* Producer creates (produces) items
* Consumer uses (consumes) items from the Producer
* The PowerShell Pipeline is a Producer-Consumer

```powershell
Get-Job | Wait-Job | Receive-Job
```

* `Get-Job` produces a list of Jobs
* `Wait-Job` consumes `Get-Jobs` results then also produces a list of jobs
* `Receive-Job` consumes `Wait-Job` results

### Producer-Consumer in Concurrent Programming

* Multiple Producers of the same item
* Multiple Consumers of those items
* Producers and Consumers Threads
* Threads are ScriptBlocks
* Increase and decrease Producers and consumers as needed

### Widget Factory Analogy

The Widget Factory turns monads into widgets.

Receiving:

* Multiple suppliers deliver monads at various times
* Sometimes Multiple suppliers deliver at once
* Receiving has multiple delivery bays
* All deliveries feed to a single monad line
* monads travel to Manufacturing

Manufacturing:

* Line workers take monads and build widgets
* Multiple line workers
* When their current widget is done they grab the next available monad
* Sometimes need Monads at the same time
* Widgets go out to Shipping

Shipping:

* Multiple pickups will be made by multiple distributors
* Sometimes multiple distributors arrive at the same time
* All shipments must have X number of widgets
* Shipping bundles the widgets and puts them on distributor trucks

### Back to Programming

* Sometimes we need to deal with more than one source of data
* Sometimes the amount of data in is to great to process serially
* Sometimes there are multiple consumers of our processed data
* Most often, this work is being broken up into batches.
* When one batch completes the next starts.
* Leads to under-utilized threads

We want all or workers 100% utilized at all times unless there is no work to be done!


### Real World Example: Inbox Rules

* Hybrid exchange with On-prem and On-cloud mailboxes
* Must enumerated all mailboxes in both
* Getting Inbox rules is a slow and expensive Task
* Multiple service accounts needed to get rules
* Service accounts cannot constantly open and close PowerShell sessions
* Throttling per-user considerations
* Rules then need to be processed and compiled into a report
* Logging and error detection

[Gist](https://gist.github.com/markekraus/2f1c376af1c69911b2421eb8c263b5f6)

### Secret Ingredients

* [Thread-Safe Collections](https://docs.microsoft.com/en-us/dotnet/standard/collections/thread-safe/)
* `BlockingCollection<PSObject>`
[Link](https://docs.microsoft.com/en-us/dotnet/api/system.collections.concurrent.blockingcollection-1?view=netframework-4.7.2)
* `ConcurrentQueue<PSObject>`
[Link](https://docs.microsoft.com/en-us/dotnet/api/system.collections.concurrent.concurrentqueue-1?view=netframework-4.7.2)
* `ConcurrentStack<Int>`
[link](https://docs.microsoft.com/en-us/dotnet/api/system.collections.concurrent.concurrentstack-1?view=netframework-4.7.2)
* `RunspacePool`
[Link](https://docs.microsoft.com/en-us/dotnet/api/system.management.automation.runspaces.runspacepool?view=powershellsdk-1.1.0)
* `PowerShell`
[Link](https://docs.microsoft.com/en-us/dotnet/api/system.management.automation.powershell?view=powershellsdk-1.1.0)

```powershell
using namespace System.Collections.Concurrent
$Queue = [BlockingCollection[PSObject]]::new(
    [ConcurrentQueue[PSObject]]::new()
)
$RunspacePool = [runspacefactory]::CreateRunspacePool(1,4)
$RunspacePool.Open()
$Runspace = [PowerShell]::Create()
$Runspace.RunspacePool = $RunspacePool
$Runspace.AddScript($ScriptBlock).AddArgument($Queue)
$Runspace.BeginInvoke()
```

### Blocking

* `BlockingCollection.GetConsumingEnumerable()`
* Blocks the thread until it can take an item
* `BlockingCollection.CompleteAdding()`
* Marks the collection complete
* `GetConsumingEnumerable()` will then exit the loop

Thread 1:

```powershell
 foreach ($LogEntry in $LogQueue.GetConsumingEnumerable()) {
     # do stuff
 }
```

Thread 2:

```powershell
$LogQueue.Add($Message1)
$LogQueue.Add($Message2)
$LogQueue.Add($Message3)
$LogQueue.CompleteAdding()
```

### Stacks for Thread Tracking

* `ConcurrentStack<Int>`
* Used to track how peer threads
* last thread completes the output queue

```powershell
 $FileConsumerStack.Add(
    [System.Threading.Thread]::CurrentThread.ManagedThreadId
)
# do stuff
# Remove a thread from the stack
$null = $FileConsumerStack.Take()
# Close LogQueue if this is the last thread
if($FileConsumerStack.Count -lt 1) {
    $FileConsumerStack.CompleteAdding()
    $LogQueue.CompleteAdding()
}
```

### Demo

* Enumerate files in multiple folders
* Take the Filenames and reverse them
* Log new names

[Main Demo](./05-MainDemo.ps1)

### Demo Notes

* Threads are started before any folders are supplied
* Toggling the number of File Producers and File Consumers
* Can have more File producers than Folders
* Single log consumer to prevent file locks
