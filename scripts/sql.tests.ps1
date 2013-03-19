function Get-CurrentDirectory
{
  $thisName = $MyInvocation.MyCommand.Name
  [IO.Path]::GetDirectoryName((Get-Content function:$thisName).File)
}

Import-Module (Join-Path (Get-CurrentDirectory) 'sql.psm1') -DisableNameChecking -Force

    

    
    Describe "Get-Server" -Tags "Sql Functions" {


        Context "Windows Auth" { 
            $localinstance = Get-Default-Sql-Instance
            $result = Get-Server "$localinstance"
            $expectedusername = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            It "Should take instance name only" { 
                $result.ConnectionContext.TrueLogin  | Should Be $expectedusername
            }
        }

        Context "Validate Parameter Input" {
            It "Should fail if no instance name is provided" {
                { Get-Server } | Should Throw 
            }

            It "Should fail if empty instance name is provided" {
                   { Get-Server $null} | Should Throw                      
            }
             
            It "Should fail if no instance name but sql parameters are provided" {
                { Get-Server $null "aasdf" "basdfd"} | Should Throw 
            }
        }        
    }
