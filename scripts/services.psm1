

function Kill-Services([string] $name, [bool] $exactmatch) { 

    Write-Host "Killing all services with $name exactmatch set to $exactmatch"

    if($exactmatch) { 
        $services = Get-Service | Where-Object {$_.name -eq $name}
    } else { 
        $services = Get-Service | Where-Object {$_.name.Contains($name)}
    }

    foreach($service in $services) { 

         Write-Host "Killing service " $service.displayname
         if($service.status -eq "Running") 
        {
            Stop-Service -Displayname $service.displayname -force
        }
    }
}






