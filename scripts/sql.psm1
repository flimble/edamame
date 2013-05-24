function Get-CurrentDirectory
{
    $thisName = $MyInvocation.MyCommand.Name
    [IO.Path]::GetDirectoryName((Get-Content function:$thisName).File)
}

function Get-Default-Sql-Instance
{
  $instances = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server').InstalledInstances
  if($instances.count -gt 0) {
    $result = $instances[0]

    if($result -eq "MSSQLSERVER") {
      return "(local)"
    }
    else {
      return ".\$result"
    }
  }
  else {
    return $null
  }
}

function Invoke-Sqlcmd2
{
    param(
    [string]$ServerInstance,
    [string]$Database,
    [string]$Query,
    [Int32]$QueryTimeout=30,
    [string]$username,
    [string]$password
    )

      if ($username) { 
        $ConnectionString = "Server={0};Database={1};User ID={2};Password={3};Trusted_Connection=False;Connect Timeout={4}" -f $ServerInstance,$Database,$Username,$Password,$QueryTimeout 
      }  
      else { 
        $ConnectionString = "Server={0};Database={1};Integrated Security=True;Connect Timeout={2}" -f $ServerInstance,$Database,$QueryTimeout
      }   
    

    c-using($conn=new-object System.Data.SqlClient.SQLConnection) {

      Write-Host $connectionstring

      $conn.ConnectionString= $connectionstring

      $conn.Open()
      $cmd=new-object system.Data.SqlClient.SqlCommand($Query,$conn)
      $cmd.CommandTimeout=$QueryTimeout
      $ds=New-Object system.Data.DataSet
      $da=New-Object system.Data.SqlClient.SqlDataAdapter($cmd)
      [void]$da.fill($ds)
      $conn.Close()
      return $ds.Tables[0]    
  }
  
}

$script:typesLoaded = $false
function Load-Types
{
  if ($script:typesLoaded) { return }

  #needs SQL SMO goop - http://www.microsoft.com/download/en/details.aspx?displaylang=en&id=16177
  #needs MSXML 6, SQL CLR types and SQL Native Client
  #9.0 needed for 2005, 10.0 needed for 2008
  Add-Type -AssemblyName 'System.Data',
    ('Microsoft.SqlServer.ConnectionInfo, Version=10.0.0.0, Culture=neutral, ' +
      'PublicKeyToken=89845dcd8080cc91'),
    ('Microsoft.SqlServer.Smo, Version=10.0.0.0, Culture=neutral, ' +
      'PublicKeyToken=89845dcd8080cc91'),
    ('Microsoft.SqlServer.Management.Sdk.Sfc, Version=10.0.0.0, Culture=neutral,' +
      ' PublicKeyToken=89845dcd8080cc91'),
    ('Microsoft.SqlServer.SqlEnum, Version=10.0.0.0, Culture=neutral, ' +
      'PublicKeyToken=89845dcd8080cc91'),
    ('Microsoft.SqlServer.SmoExtended, Version=10.0.0.0, Culture=neutral, ' +
      'PublicKeyToken=89845dcd8080cc91')

    $script:typesLoaded = $true
}

function Start-ServiceAndWait
{
  param
  (
    [Parameter(Mandatory=$true)]
    [string]
    [ValidateScript({Get-Service | ? { $_.Name -eq $serviceName }})]
    $ServiceName,

    [Parameter(Mandatory=$false)]
    [int]
    [ValidateRange(1, 30)]
    $MaximumWaitSeconds = 15,

    [Parameter()]
    [switch]
    $StopFirst
  )

  $service = Get-Service | ? { $_.Name -eq $serviceName }
  if (-not $service) { throw "Service $ServiceName does not exist" }

  if ($StopFirst -or ($service.Status -ne 'Running'))
  {
    $identity = [Security.Principal.WindowsPrincipal] `
      ([Security.Principal.WindowsIdentity]::GetCurrent())
    $isAdmin = $identity.IsInRole(
      [Security.Principal.WindowsBuiltInRole]::Administrator)
    if (! $isAdmin)
      { throw "Must be in Administrator role to start / stop service" }

    if ($StopFirst -and ($service.Status -eq 'Running'))
    {
      Write-Host -ForeGroundColor Magenta `
        "Stopping Service [$serviceName]"
      $service | Stop-Service
    }
    $service | Start-Service
    $seconds = 0
    while (($seconds -lt $MaximumWaitSeconds) -and `
      ((Get-Service $serviceName).Status -ne 'Running'))
    {
      Write-Host "Waiting on [$serviceName] to start..."
      sleep 1
      $seconds++
    }
    if ((Get-Service $serviceName).Status -ne 'Running')
    {
      throw { "Failed to start service in $seconds seconds" }
    }
  }

  Write-Host -ForeGroundColor Magenta `
    "Service [$serviceName] is running"
}

function Shrink-SqlDatabase([string] $InstanceName, [string] $DatabaseName, [int] $percentFree=0, [string] $username, [string] $password) { 
  Load-Types

  Write-Host "Shrinking database $DatabaseName on $InstanceName"

  try { 
      $server = Get-Server $instancename $username $password
      $server.ConnectionContext.StatementTimeout = 65534

      $database = $server.Databases[$DatabaseName]
      
      Write-Host "found database: $database and starting shrink using Microsoft.SqlServer.Management.Smo.ShrinkMethod:Default leaving '$percentFree' percent free."
      $database.Shrink($percentFree,
        [Microsoft.SqlServer.Management.Smo.ShrinkMethod]::Default)
  }
  catch { 
    $message = $_.Exception.GetBaseException().Message
    Write-Host $_.Exception
    Write-Host $_.Exception.GetBaseException()
    throw $message  
  }
  finally
  {
    if ($server) { $server.ConnectionContext.Disconnect() }
  }

}

function ConvertKbToMb([int] $kb) {
  return $kb / 1024

}

function Shrink-SqlLogFiles([string] $InstanceName, [string] $DatabaseName, [int] $percentFree=0, [string] $username, [string] $password) { 
  Load-Types

  Write-Host "Shrinking log files for $DatabaseName on $InstanceName"

  try { 

      $fractionFree = $percentFree
      if($percentFree > 0) { 
        $fractionFree = $percentFree / 100;
      }

      $server = Get-Server $instancename $username $password

      $database = $server.Databases[$DatabaseName]

      [Microsoft.SqlServer.Management.Smo.RecoveryModel] $originalRecoveryModel = $database.RecoveryModel
      $database.RecoveryModel = [Microsoft.SqlServer.Management.Smo.RecoveryModel]::Simple
      $database.alter();

      Write-Host "Changing database recovery model from $originalRecoveryModel to Simple"

      foreach($logFile in $database.LogFiles)
      {          
        $newSize = 0;
        $totalLogSizeMB = ($logFile.Size / 1024);

        if($percentFree -gt 0) {
          [int]$newSizeMB = ($totalLogSizeMB * ($percentFree / 100))
        }

        Write-Host ("Shrinking down {0} to {1} MB of {2}" -f $logFile.Name, $newSizeMB, $totalLogSizeMB)
        $logFile.Shrink($newSizeMB, [Microsoft.SqlServer.Management.Smo.ShrinkMethod]::Default) | out-null
      }

      $database.RecoveryModel = $originalRecoveryModel
      $database.alter();

  }
  finally
  {
    if ($server) { $server.ConnectionContext.Disconnect() }
  }

}


function IsNullOrEmpty($variable) {if ($variable) {$true} else {$false}}

function Get-Server
{
  param
  (
    [ValidateNotNullOrEmpty()]
    [string]
    $instancename = $(throw "instancename parameter is required."),

    [string] $username,

    [string] $password
  ) 
    Load-Types

    $server = New-Object Microsoft.SqlServer.Management.Smo.Server($InstanceName)

    if($username){ 
      Write-Host "using sql credentials"

      #This sets the connection to mixed-mode authentication 
      $server.ConnectionContext.LoginSecure=$false; 


      #This sets the login name 
      $server.ConnectionContext.set_Login($username); 

      #This sets the password 
      $server.ConnectionContext.set_Password($password)  
    }

    return $server
   
}

function Set-Recovery-Mode ([string] $instancename, [string] $username, [string] $password) { 

}

#http://stackoverflow.com/questions/5123423/error-restoring-database-backup-to-new-database-with-smo-and-powershell
function Backup-SqlDatabase
{
  <#
  .Synopsis
    Will generate a copy of an existing SQL server database using the SMO
    backup methods.
  .Description
    The given service is checked to ensure it's running.

    The given database name is copied to a backup file using the SMO
    Backup class.  This will work on a live database; what is generated
    is considered a snapshot appropriate for a restore.

    The backup mechanism is much faster than Transfer, but may be less
    appropriate for a live database.

    The written file is named $DatabaseName.bak and is written to the
    given BackupPath.

    Requires that SMO and some SQL server be installed on the local machine
  .Parameter DatabaseName
    The original name of the database.
  .Parameter BackupPath
    The directory to write the backup file to, not including file name.
  .Parameter ServiceName
    The name of the SQL Server service name - will default to
    MSSQL$SQLEXPRESS if left unspecified.
  .Parameter InstanceName
    The name of the SQL server instance. By default, .\SQLEXPRESS
  .Outputs
    A string containing the backup filename.
  .Example
    Backup-SqlDatabase -DatabaseName MyDatabase -BackupPath c:\db

    Description
    -----------
    Will use the default localhost SQLEXPRESS instance and will create a
    backup file named c:\db\MyDatabase.bak

    Outputs c:\db\MyDatabase.bak
  #>
  [CmdletBinding()]
  param(

    [Parameter(Mandatory=$false)]
    [string]
    $InstanceName = '.\SQLEXPRESS',

    [Parameter(Mandatory=$true)]
    [string]
    $DatabaseName,

    [Parameter(Mandatory=$true)]
    [string]
    $BackupPath,

    [string] $username, 

    [string] $password

  )

  Load-Types

  try
  {
    $backupFilePath = "$BackupPath\$DatabaseName.bak"

    Write-Host "Backing up database $databasename on $instancename to $backupfilepath"


    $server = Get-Server $instancename $username $password
    $smoBackup = New-Object Microsoft.SqlServer.Management.Smo.Backup

    $smoBackup.Action =
      [Microsoft.SqlServer.Management.Smo.BackupActionType]::Database
    $smoBackup.BackupSetDescription = "Full Backup of $DatabaseName"
    $smoBackup.BackupSetName = "$DatabaseName Backup"
    $smoBackup.Database = $DatabaseName
    $smoBackup.Incremental = $false
    $smoBackup.LogTruncation =
      [Microsoft.SqlServer.Management.Smo.BackupTruncateLogType]::Truncate
    $smoBackup.Devices.AddDevice($backupFilePath,
      [Microsoft.SqlServer.Management.Smo.DeviceType]::File)
    Write-Host "Generating [$backupFilePath] for [$DatabaseName] on [$instancename]"
    $smoBackup.SqlBackup($server)

    return $backupFilePath
  }
  finally
  {
    if ($server) { $server.ConnectionContext.Disconnect() }
  }
}

function Restore-SqlDatabase
{
<#
.Synopsis
  Will restore a given SQL backup file to a new database using SMO, and
  a backup file generated by Backup-SqlDatabase.
.Description
  The given service is checked to ensure it's running and then a new
  database is created with the given destination name, as restored from
  the backup file.  If the database already exists, an error occurs.

  This is not allowed to replace an existing database of the same name.

  The database is detached after the cmdlet is run, unless -NoDetach is
  specified.

  Requires that SMO and some SQL server be installed on the local machine
.Parameter BackupPath
  The complete path to the SQL backup file.
.Parameter DestinationDatabasePath
  The final output database path, not including the file name.
.Parameter DestinationDatabaseName
  The final output database filename.  Both MDF and LDF will assume this
  name.
.Parameter NoDetach
  Will disable the database from being detached after creation. This will
  allow the database to be used in, for instance, integration tests.

  Default is to detach the database.
.Parameter KillAllProcesses
  Will instruct the SQL Server instance to kill all the processes
  associated with the DestinationDatabaseName, should there be any.  In
  build scenarios, this is not typically needed.

  Default is to not kill all processes
.Parameter ServiceName
  The name of the SQL Server service name - will default to
  MSSQL$SQLEXPRESS if left unspecified.
.Parameter InstanceName
  The name of the SQL server instance. By default, .\SQLEXPRESS
.Example
  Restore-SqlDatabase -BackupPath c:\db\foo.bak `
    -DestinationDatabasePath c:\db -DestinationDatabaseName MyDatabase2

  Description
  -----------
  Will use the default localhost SQLEXPRESS instance and setup a new
  SQL MDF on disk, based on a restore from the given .bak file.
  The database files will be placed into c:\db\MyDatabase2.mdf
#>
  [CmdletBinding()]
  param(
    [string]
    [ValidateScript({ (Test-Path $_) -and (!(Get-Item $_).PSIsContainer) })]
    $BackupPath,

    $InstanceName, 

    [string]
    $DestinationDatabasePath,

    [string]
    $DestinationDatabaseName,

    [Switch]
    $NoDetach = $true,

    [Switch]
    $KillAllProcesses = $false,

    [string] $username,

    [string] $password
  )

  Load-Types

  try
  {
    $dataFilepath = "$DestinationDatabasePath\$DestinationDatabaseName.mdf"
    Write-Host "data file target: $datafilepath"
    $logFilePath = "$DestinationDatabasePath\$DestinationDatabaseName" + "_Log.ldf"
    Write-Host "log file target: $logfilepath"

    if (Test-Path $dataFilepath) { throw "$dataFilepath already exists!" }

    $server = Get-Server $instancename $username $password

    $server.ConnectionContext.StatementTimeout = 0

    # http://www.sqlmusings.com/2009/06/01/how-to-restore-sql-server-databases-using-smo-and-powershell/
    #http://stackoverflow.com/questions/1466651/how-to-restore-a-database-from-c-sharp
    $backupDevice = New-Object Microsoft.SqlServer.Management.Smo.BackupDeviceItem($BackupPath, 'File')
    $smoRestore = New-Object Microsoft.SqlServer.Management.Smo.Restore

    

    $smoRestore.Database = $DestinationDatabaseName
    $smoRestore.NoRecovery = $false
    $smoRestore.ReplaceDatabase = $true
    $smoRestore.FileNumber = 1
    $smoRestore.Action = [Microsoft.SqlServer.Management.Smo.RestoreActionType]::Database


    #show every 10% progress
    $smoRestore.PercentCompleteNotification = 10;
    $smoRestore.Devices.Add($backupDevice)
    

    # Get the file list from backup file
    $dbFileList = $smoRestore.ReadFileList($server)
    Write-Host "Backup logical data name: " $dbFileList.Select("Type = 'D'")[0].LogicalName
    Write-Host "Backup logical log name: " $dbFileList.Select("Type = 'L'")[0].LogicalName





    $smoRestoreDataFile = New-Object("Microsoft.SqlServer.Management.Smo.RelocateFile")
    $smoRestoreDataFile.LogicalFileName = $dbFileList.Select("Type = 'D'")[0].LogicalName
    $smoRestoreDataFile.PhysicalFileName = $dataFilepath

    $smoRestoreLogFile = New-Object("Microsoft.SqlServer.Management.Smo.RelocateFile")
    $smoRestoreLogFile.LogicalFileName = $dbFileList.Select("Type = 'L'")[0].LogicalName
    $smoRestoreLogFile.PhysicalFileName = $logFilePath



    # The logical file names should be the logical filename stored in the backup media
    # Add the new data and log files to relocate to
    $smoRestore.RelocateFiles.Add($smoRestoreDataFile)
    $smoRestore.RelocateFiles.Add($smoRestoreLogFile)
    
    


    if ($server.Databases.Contains($DestinationDatabaseName))
    {
      throw "Database $DestinationDatabaseName already exists!"
    }

  
    Write-Host ("Restoring [$BackupPath] to [$DestinationDatabaseName]" + "at [$dataFilepath]")
    $smoRestore.SqlRestore($server)
  }
  catch { 
    $message = $_.Exception.GetBaseException().Message
    Write-Host $_.Exception
    Write-Host $_.Exception.GetBaseException()
    throw $message
  }
  finally
  {
    if ($server)
    {
      if ($DestinationDatabaseName -and (-not $NoDetach))
      {
        $server.DetachDatabase($DestinationDatabaseName, $true)
      }
      $server.ConnectionContext.Disconnect()
    }
  }
}
function Remove-SqlDatabase
{
<#
.Synopsis
  Will detach an existing SQL server database using SMO.
.Description
  The given service is checked to ensure it's running and then the script
  is executed.  If the database already exists, an error occurs.

  The database is detached using the DetachDatabase SMO Api call.

  Requires that SMO and some SQL server be installed on the local machine
.Parameter DatabaseName
  The name of the database to detach.
.Parameter ServiceName
  The name of the SQL Server service name - will default to
  MSSQL$SQLEXPRESS if left unspecified.
.Parameter InstanceName
  The name of the SQL server instance. By default, .\SQLEXPRESS
.Parameter Force
  Optionally forces detachment of the database.  When leaving a DB in
  multi-user mode, it is possible to have lingering connections from
  integration tests.  This option will ensure detachment of the DB by
  forcibly killing all active processes on the database.
.Example
  Remove-SqlDatabase -DatabaseName MyDatabase

  Description
  -----------
  Will use the default localhost SQLEXPRESS instance and will detach
  MyDatabase.
#>
  param(
    [string]
    $DatabaseName,


    [string]
    $InstanceName = '.\SQLEXPRESS',

    [switch]
    $Force = $true,

    [string] $username,

    [string] $password

  )

  Load-Types
  #Start-ServiceAndWait $ServiceName

  Write-Host "Detaching $DatabaseName from $InstanceName"
  try
  {
    $server = Get-Server $instancename $username $password

    if ($Force)
    {
      <#
        Re-Added this as this is in the example here: http://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.server.killdatabase(v=sql.110).aspx
        and decompile shows that KillDatabase in Microsoft.SqlServer.Smo.dll does not call KillAllProcesses. Contrary to some blog posts. 
      #>
      try 
      { 
        Write-Host "Killing All Processes on $DatabaseName"
        $server.KillAllProcesses($DatabaseName) | Out-Null
      } 
      catch 
      { 
        Write-Host "Ignoring failed attempt to KillAllProcesses. Proceeding to Run KillDatabase"
      }
      
      Write-Host "Killing Database $DatabaseName"
      $server.KillDatabase($DatabaseName) | Out-Null
    }
    else
    {
      Write-Host "Detaching Database $DatabaseName"
      $server.DetachDatabase($DatabaseName, $true)
    }

  }
  catch { 
    $message = $_.Exception.GetBaseException().Message
    throw $message
  }
  finally
  {
    if ($server) { $server.ConnectionContext.Disconnect() }
  }
}

function Database-Exists([string] $InstanceName, [string] $DatabaseName, [string] $username, [string] $Password) { 
  Load-Types

 Write-Host "Checking if on $DatabaseName exists on  $InstanceName"
  try
  {
    $server = Get-Server $instanceName $UserName $password

    return $server.Databases.Contains($DatabaseName)
  }
  finally
  {
    if ($server) { $server.ConnectionContext.Disconnect() }
  }

}

function Sql-Database-Kill-Connections([string] $instance, [string] $database, [string] $sqluser, [string] $sqlpassword) { 
    Load-Smo-Assemblies

    try { 
      $smoserver = new-object Microsoft.SqlServer.Management.Smo.Server($instance)

      Write-Host "Killing process and dropping database $dbName"
      $smoserver.killallprocesses($database)

      $existingDB = $smoserver.databases[$database];
      if($existingDB)
      {    
          Write-Host "Dropping $database"
          $existingDB.drop()     
      }
    }
    catch {
      $message = $_.Exception.GetBaseException().Message
      throw $message
      
    }
    finally {
      $smoserver.Dispose
    }
}

function Execute-Sql(
        [string] $instance=$(throw "instance name is required")
        ,[string] $database=$(throw "database name is required")
        ,[string] $command=$(throw "command is required")
        ,[int] $queryTimeout=30        
        ,$sqluser=$null
        ,$sqlpassword=$null) { 

    Load-Snapin "SqlServerCmdletSnapin100"
    Load-Snapin "SqlServerProviderSnapin100"    

    if($sqluser -ne $null) { 
        Write-Host "Running query as SQL user $sqluser against dastabase $database on $instance"
        Invoke-Sqlcmd2 -Query $command -Database $database -ServerInstance $instance -UserName $sqluser -Password $sqlpassword -QueryTimeout $queryTimeout
    }
    else { 
        Write-Host "Running query as current window suer against dastabase $database on $instance"
        Invoke-Sqlcmd2 -ServerInstance $instance -Database $database -Query $command -QueryTimeout $queryTimeout
    }
    
}



function Load-Snapin($snapIn) { 
    if (!(Get-PSSnapin | ?{$_.name -eq $snapIn})) 
    { 
        if(Get-PSSnapin -registered | ?{$_.name -eq $snapIn}) 
        { 
            add-pssnapin $snapIn 
            write-host "Loading $snapIn in session" 
        } 
        else 
        { 
            write-host "$snapIn is not registered with the system." 
            break 
        }
     
    } 
    else 
    { 
        write-host "$snapIn is already loaded" 
    } 
}



function c-using {
    param (
        [System.IDisposable] $inputObject = $(throw "The parameter -inputObject is required."),
        [ScriptBlock] $scriptBlock = $(throw "The parameter -scriptBlock is required.")
    )
    
    Try {
        &$scriptBlock
    } Finally {
        if ($inputObject -ne $null) {
            if ($inputObject.psbase -eq $null) {
                $inputObject.Dispose()
            } else {
                $inputObject.psbase.Dispose()
            }
        }
    }
}