function Get-CurrentDirectory
{
    $thisName = $MyInvocation.MyCommand.Name
    [IO.Path]::GetDirectoryName((Get-Content function:$thisName).File)
}


$base_dir = Get-CurrentDirectory
Write-Host "Importing all Edamame script files from dir: $base_dir"
import-module (join-path $base_dir general.psm1) -DisableNameChecking -force 
import-module (join-path $base_dir sql.psm1) -DisableNameChecking -force 
import-module (join-path $base_dir services.psm1) -DisableNameChecking -force 
import-module (join-path $base_dir teamcity.psm1) -DisableNameChecking -force 
import-module (join-path $base_dir build.psm1) -DisableNameChecking -force 

