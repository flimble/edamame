
function Get-File-Exists-On-Path
{
    param(
        [string]$file
    )
    $results = ($Env:Path).Split(";") | Get-ChildItem -filter $file -erroraction silentlycontinue
    $found = ($results -ne $null)
    return $found
}

function Get-Git-Commit
{
    if ((Get-File-Exists-On-Path "git.exe")){
        $gitLog = git log --oneline -1
        return $gitLog.Split(' ')[0]
    }
    else {
        return "0000000"
    }
}

function ilmerge($key, $directory, $name, $assemblies, $extension)
{    
    # Create a new temp directory as we cannot overwrite the main assembly being merged.
    new-item -path $directory -name "temp_merge" -type directory -ErrorAction SilentlyContinue
    
    # Unfortuntately we need to tell ILMerge its merging CLR 4 assemblies.
    if($framework -eq "4.0")
    {
        Exec { tools\ilmerge\ilmerge.exe /keyfile:$key /out:"$directory\temp_merge\$name.$extension" "$directory\$name.$extension" $assemblies /targetplatform:"v4,$env:ProgramFiles\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.0" }
    }
    else
    {
        Exec { tools\ilmerge\ilmerge.exe /keyfile:$key /out:"$directory\temp_merge\$name.$extension" "$directory\$name.$extension" $assemblies }
    }
    
    Get-ChildItem "$directory\temp_merge\**" -Include *.dll, *.pdb | Copy-Item -Destination $directory
    Remove-Item "$directory\temp_merge" -Recurse -ErrorAction SilentlyContinue
}

function Get-Version-From-Git-Tag
{
  $gitTag = git describe --tags --abbrev=0
  return $gitTag.Replace("v", "") + ".0"
}

function Verify-Net-45-Installed {

    if( (ls "$env:windir\Microsoft.NET\Framework\v4.0*") -eq $null ) {
        throw ".Net 4.0 install directory cannot be found on windows path"
    }

    $version = (get-itemproperty 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full').Version
    if(! $version.StartsWith("4.5")) {
        throw ".NET 4.5 not found in registry"
    }
}

function Set-ConfigAppSetting
    ([string]$PathToConfig=$(throw 'Configuration file is required'),
         [string]$Key = $(throw 'No Key Specified'), 
         [string]$Value = $(throw 'No Value Specified'),
         [Switch]$Verbose,
         [Switch]$Confirm,
         [Switch]$Whatif)
{
    $AllAnswer = $null
    if (Test-Path $PathToConfig)
    {
        Write-Host "updating $Key in config $PathToConfig "
        $x = [xml] (type $PathToConfig)
 
            $node = $x.configuration.SelectSingleNode("appSettings/add[@key='$Key']")
            $node.value = $Value
            $newXml = Format-Xml $x
            Set-Content $PathToConfig $newXml
    }
} 

function Format-XML ([xml]$xml, $indent=2) 
{ 
    $StringWriter = New-Object System.IO.StringWriter 
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter 
    $xmlWriter.Formatting = "indented" 
    $xmlWriter.Indentation = $Indent 
    $xml.WriteContentTo($XmlWriter) 
    $XmlWriter.Flush() 
    $StringWriter.Flush() 
    $result =  $StringWriter.ToString() 
    return $result
}

function Get-ConfigAppSetting
([string]$PathToConfig=$(throw 'Configuration file is required'))
{
    if (Test-Path $PathToConfig)
    {
        $x = [xml] (type $PathToConfig)
        $x.configuration.appSettings.add
    }
    else
    {
        throw "Configuration File $PathToConfig Not Found"
    }
}

function Roundhouse-Kick-Database 
([string]$DatabaseName=$(throw 'DatabaseName is required'),
 [string]$TargetServer=$(throw 'TargetServer is required'),
 [string]$Environment=$(throw 'Environment is required'),
 [bool]$UseSqlAuthentication=$false,
 [string]$LoginUser="",
 [string]$LoginPassword="",
 [bool]$DropCreate=$true,
 [bool]$RestorefromBackup=$false,
 [string]$BackupFile="",
 [string]$CustomCreateScript=""
 )
{ 
    $SqlFilesDirectory = "$DatabaseName.Database"
    $RepositoryPath="$/SAIGPS Team Project/SAIGPS/Trunk"

    $args = @()

    if($RestorefromBackup -eq $true) {
        $args += @("--restore",
        "--restoretimeout=9000",
        "--commandtimeoutadmin=9000",
        "--restorefrom=$BackupFile")
    }

    if($CustomCreateScript) {
        Write-Host "Using Custom Creation Script $CustomCreateScript"
        $args += @("--createdatabasecustomscript=$CustomCreateScript")
    }


    if($UseSqlAuthentication -eq $true) {
        $args += @("--connectionstring=server=$TargetServer;database=$DatabaseName;uid=$LoginUser;pwd=$LoginPassword")
    }





    if($DropCreate -eq $true) {
        exec { roundhouse\console\rh.exe --servername=$TargetServer --database=$DatabaseName --noninteractive --drop }
    }

    Write-Host "Running roundhouse with the following arguments"
    $args | foreach { write-host $_ }

    exec { roundhouse\console\rh.exe --servername=$TargetServer --database=$DatabaseName --environment=$Environment --sqlfilesdirectory=$SqlFilesDirectory --repositorypath=$RepositoryPath --upfolder="2.Tables and Data (MODIFICATIONS WILL REQUIRE DATABASE REFRESH)" --runfirstafterupdatefolder="3.Synonyms (MODIFICATIONS WILL REQUIRE DATABASE REFRESH)" --functionsfolder="4.Functions (DROP CREATE)" --viewsfolder="5.Views (DROP CREATE)" --sprocsfolder="6.Stored Procedures (DROP CREATE)" --indexesfolder="7.Indexes (DROP CREATE)" --runAfterOtherAnyTimeScripts="8.Environment Configuration Data" --permissionsfolder="9.SQL Server Permissions" --noninteractive --commandtimeout=1200 $args }    
    

    
}


function Install-Nuget-Packages([string]$packages_dir=$(throw 'Target packages directory is required')) { 
    $nuget_exe = '.nuget\nuget.exe'

    if( (Test-Path $nuget_exe) -eq $false ) {
        throw "nuget.exe cannot be found on path"
    }

    $configs = Get-ChildItem -filter "packages.config" -recurse
    

    foreach($config in $configs)
    {
        $fullname = $config.fullname

        exec { & $nuget_exe install "$fullname" -o  "$packages_dir" }
    }
}

function Generate-Environment-Config([string]$config=$(throw 'Config path is required'),
    [string]$applicationName=$(throw 'application name is required'),
    [string]$environmentName=$(throw 'environment name is required')) 
{
    
}

function Update-SourceVersion
{
  Param ([string]$Version)
  $NewVersion = 'AssemblyVersion("' + $Version + '")';
  $NewFileVersion = 'AssemblyFileVersion("' + $Version + '")';

  foreach ($o in $input) 
  {
    Write-output $o.FullName
    $TmpFile = $o.FullName + ".tmp"

     get-content $o.FullName | 
        %{$_ -replace 'AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', $NewVersion } |
        %{$_ -replace 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', $NewFileVersion }  > $TmpFile

     move-item $TmpFile $o.FullName -force
  }
}


function Update-AllAssemblyInfoFiles ([string] $sourcePath,  [string] $assemblyinfo_version)
{
    $r= [System.Text.RegularExpressions.Regex]::Match($assemblyinfo_version, "^[0-9]+(\.[0-9]+){1,3}$");   
    if($r.Success -eq $false) {
        throw "invalid version number provided"
    }
    

   $oldDir = get-location 

     cd $sourcePath
    
  foreach ($file in "AssemblyInfo.cs", "AssemblyInfo.vb" ) 
  {  
    get-childitem -recurse |? {$_.Name -eq $file} | Update-SourceVersion $assemblyinfo_version ;
  }

  cd $oldDir
}



function copy-assemblies-only($source, $targetDir) { 

    write-host "copying assemblies from $source to $targetDir"
    new-item $targetDir -itemType Directory -ErrorAction SilentlyContinue | out-null

    Copy-Item $source -Recurse -include @("*.dll","*.exe") -Destination $targetDir  
}

function xcopy-directory-with-contents($source, $exclusions, $targetDir, [bool]$removeEmptyFolders) {
    $tempfile = [IO.Path]::GetTempFileName()

    if($exclusions) {
        Set-Content $tempfile ([System.String]::Join("`r`n", $exclusions))
        gc $tempfile
    }

    write-host "copying files from $source to $targetDir"

    &xcopy $source $targetDir /EXCLUDE:$tempfile /e  | out-null
    remove-item $tempfile

    if($removeEmptyFolders) {Remove-EmptyFolders $targetDir}
}


function Remove-EmptyFolders { 
 [CmdletBinding()] 
  param ($Path='.\') 
   
$delDirs = @() 
$dirs = Get-ChildItem -Path $Path -Recurse | Where-Object { ($_.PsIsContainer) } 
foreach ($dir in $dirs) { 
    $l = 0 
    $files = Get-ChildItem $dir.PSPath -Recurse | Where-Object { (!($_.PsIsContainer)) } 
    foreach ($file in $files) { 
        $l += $file.length 
        } # end foreach $file 
    if ($l -eq 0) { 
        Write-Verbose "$($dir.pspath | split-path -noqualifier) has no files"  
        $delDirs += $dir.PSPath 
        } # end if 
    } # end foreach $dir 
 
if ($delDirs) { 
    Write-Host "The following empty directories will be removed." 
    $delDirs | ForEach-Object { Split-Path $_ -NoQualifier } 
    
        $delDirs | Remove-Item -Recurse -ErrorAction SilentlyContinue -Force  
        Write-Host "$($delDirs.count) directories deleted" 
    } # end if 
else {Write-Host "No empty folders were found"} 
} # end function


function OutputNunitTestSummaryToConsole($results_xml, $nunitsummary_path) { 
    if(!(test-path $results_xml)) { throw "no test results found to report at $results_xml"}
    if(!(test-path $results_xml)) { throw "cannot find nunit-summary at $nunitsummary_path"}


    exec { &"$nunitsummary_path" $results_xml -noheader -brief }

    [xml]$xml = get-content $results_xml

    $testfailures = $xml | select-xml -xpath '//test-case' | where-object { $_.Node.success -eq "False"} 
    
    foreach($failure in $testfailures) { 
        write-host

        write-host "Error Name: " -foregroundcolor darkred
        write-host $failure.Node.name -foregroundcolor red
        write-host
        write-host "Error Description: " -foregroundcolor darkred       
        write-host $failure.Node.description -foregroundcolor red

        foreach($child in $failure.Node.ChildNodes) {
            if($child.Name -eq "failure") { 
                foreach($nestedChild in $child.ChildNodes) {
                    if($nestedChild.Name -eq "message") { 
                        Write-Host $nestedChild.InnerXml -foregroundcolor red
                    }
                }
            }   
        }   
    }   
    $xml = $null   
}
