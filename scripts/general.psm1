
function Start-Remote-Session([string]$computername=$(throw "computer name is required"), $cred) {

    Write-Host "Entering PS-Session on $computername"
    New-PSSession -computername $computername -Credential $cred
}

function Clear-Remote-Sessions([string]$computername=$(throw "computer name is required"), $cred) { 
    Write-Host "Closing remote Ps-Sessions on $computername"
    try {
        $opensession = get-pssession -ComputerName $computername -ErrorAction SilentlyContinue -Credential $cred

        if($opensession -ne $null) {
            remove-pssession $opensession -Credential $cred
        }

    }
    catch {
    }    
}



function Strip-Non-AlphaNumeric-Chars([string] $toStrip) { 
    return $toStrip -replace "[^a-zA-Z0-9]", '' 
}

function Get-App-Pools { 
    Load-WebAdmin

    get-childitem 'iis:\apppools'
}

Function Load-WebAdmin {
  $webAdminModule = get-module -ListAvailable | ? { $_.Name -eq "webadministration" }
  If ($webAdminModule -ne $null) {
    import-module WebAdministration
  }else{
    Add-pssnapin WebAdministration
   }
}

function Get-Credential-For-User([string] $username) {
    return Get-Credential $username
}

function Get-Credential-From-File([string] $username=$(throw "username is required"), [string] $creddir=$(throw "credentials directory is required")) {
    
    $credfile = Join-Path $creddir ("{0}.pwd" -f (Strip-Non-AlphaNumeric-Chars $username))

    Write-Host "Looking for credentials in in $credfile"

    if(!(Test-Path $credfile)) {
        throw "Credential file not found"
    }

    Write-Host 'Getting Credentials from stored credential file'
    $passwordSecure = Get-Content $credfile | ConvertTo-SecureString 
    return New-Object System.Management.Automation.PSCredential ($username, $passwordSecure)        
}

function Store-Credential-InFile([System.Management.Automation.PSCredential] $credential, [string] $creddir) { 
    $filename = Strip-Non-AlphaNumeric-Chars $credential.UserName
    $credfile = "$creddir\$filename.pwd"

    $credential.Password | ConvertFrom-SecureString | Set-Content $credfile
}

#Extract password as string from an existing Network Credential
function Get-Password-From-Credential([System.Management.Automation.PSCredential] $credential) {    
    $credential.GetNetworkCredential().Password
}

# C# equivalent "using" statement to be used to ensure
# IDisposable is called when object is no longer needed. 
function local-using {
    param (
        [System.IDisposable] $inputObject = $(throw "The parameter -inputObject is required."),
        [ScriptBlock] $scriptBlock = $(throw "The parameter -scriptBlock is required.")
    )
    
    Try {
        &$scriptBlock
    }
    Catch { 
    } -Finally {
        if ($inputObject -ne $null) {
            if ($inputObject.psbase -eq $null) {
                $inputObject.Dispose()
            } else {
                $inputObject.psbase.Dispose()
            }
        }
    }
}