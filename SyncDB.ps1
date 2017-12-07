[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string] $ProjectPath
)
#Preferences
$ErrorActionPreference="Stop"

#References for Invoke-SQLCMD
if (-not(Get-Module -Name SQLPS)) {
    Write-Host "Reference not imported; Trying to import it now" -ForegroundColor Yellow
        if (Get-Module -ListAvailable -Name SQLPS) { 
    $replacementEvidence = New-Object System.Security.Policy.Evidence
    $replacementEvidence.AddHost((New-Object System.Security.Policy.Zone ([Security.SecurityZone]::MyComputer)))
    $currentAppDomain = [System.Threading.Thread]::GetDomain()
    $securityIdentityField = $currentAppDomain.GetType().GetField("_SecurityIdentity", ([System.Reflection.BindingFlags]::Instance -bOr [System.Reflection.BindingFlags]::NonPublic))
    $securityIdentityField.SetValue($currentAppDomain,$replacementEvidence)
            Push-Location
            Import-Module -Name SQLPS -DisableNameChecking
            Pop-Location
            Write-Host "Reference imported successfully" -ForegroundColor Green
        }elseif ( (Get-PSSnapin -Name SqlServerCmdletSnapin100 -ErrorAction SilentlyContinue) -eq $null ){
            cd "${env:ProgramFiles(x86)}\Microsoft SQL Server\120\DAC\bin"
            $framework=$([System.Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory())
            Set-Alias installutil "$($framework)installutil.exe"
            installutil Microsoft.SqlServer.Management.PSSnapins.dll
            installutil Microsoft.SqlServer.Management.PSProvider.dll
            Add-PSSnapin SqlServerCmdletSnapin120
            Add-PSSnapin SqlServerProviderSnapin120
        }else{
            Write-Host "Reference module is not available. See: http://blog.smu.edu/wis/2012/11/26/sql-server-powershell-module-sqlps/" -ForegroundColor Red
            exit
        }
}else{
    Write-Host "Reference already imported; No action required" -ForegroundColor Yellow
}


$projFile = Get-ChildItem -Path $ProjectPath -Filter *.sqlproj | Select-Object -First 1
if(!$projFile){
    Write-Host "This action can be performed only in DB project" -ForegroundColor Red
    return;
}

$msbuild = "${env:Windir}\Microsoft.NET\Framework\v4.0.30319\MSBuild.exe"
#Register the DLL we need; Change the path based on your environment
Add-Type -Path "${env:ProgramFiles(x86)}\Microsoft SQL Server\120\DAC\bin\Microsoft.SqlServer.Dac.dll" 

[xml]$profileXml = Get-Content -Path ([string]::Format("{0}\syncdb.publish.xml", $ProjectPath))
[string]$dbServer
[string]$dbUser
[string]$dbUPwd

#Read a publish profile XML to get the deployment options
$dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load(([string]::Format("{0}\syncdb.publish.xml", $ProjectPath)))
foreach ($item in $dacProfile.TargetConnectionString.Split(";"))
{
    $prop =$item.Split("=")
    switch ($prop[0])
    {
        'Data Source' { $dbServer = $prop[1]}        
        'User ID' { $dbUser = $prop[1]}
        'Password' {$dbUPwd = $prop[1]}
        Default {}
    }
}
if(!$dbServer -or !$dbUser -or !$dbUPwd){
    Write-Host "Connection is not configured properly; check the profile xml file" -ForegroundColor Red
    return;
}        

#functions
function GetCurrentVersion($profileXml, [bool] $clientVersion){
    $version = 0   
    $connection = New-Object System.Data.SqlClient.SqlConnection
    $connection.ConnectionString = $profileXml.Project.PropertyGroup.TargetConnectionString
    $connection.Open()

    $connection.ChangeDatabase($profileXml.Project.PropertyGroup.TargetDatabaseName)

    $command = New-Object System.Data.SqlClient.SqlCommand
    $command.Connection = $connection
    if($clientVersion){
        $command.CommandText = "SELECT MAX(VersionNo) dbVersion FROM DBVersionInfo_Client"
    }
    else {
        $command.CommandText = "SELECT MAX(VersionNo) dbVersion FROM DBVersionInfo"       
    }
    $reader = $command.ExecuteReader();

    if($reader.Read()){
        $val=$reader[0]
        if(!([DBNull]::Value).Equals($val)){
            $version =$val
        } 
    }        

    $connection.Close();
    
    return $version
}

#executing prerequisites
[string] $prerequisitesScript=[string]::Format("{0}\SyncDBPrerequisitesScript.sql", $ProjectPath)
if(Test-Path $prerequisitesScript){
    Write-Host "executing $prerequisitesScript" -ForegroundColor DarkMagenta    
    #DO EXECUTE FILE    
    Invoke-Sqlcmd -InputFile $prerequisitesScript -ServerInstance $dbServer -Username $dbUser -Password $dbUPwd -Database $dacProfile.TargetDatabaseName
    Write-Host "execution completed $prerequisitesScript" -ForegroundColor DarkMagenta
}

#get the current version of DB
[int]$currentDBVersion = GetCurrentVersion -profileXml $profileXml -clientVersion $false
[int]$targetDBVersion = $currentDBVersion + 1

Write-Host "Current DB Version: $currentDBVersion" -ForegroundColor Cyan
Write-Host "Checking for upgrade scripts..." -ForegroundColor DarkGray

[string] $nextFileName = [string]::Format("{0}\UpgradeScripts\{1}.sql", $ProjectPath,$targetDBVersion.ToString("D4"))
while(Test-Path $nextFileName){
    Write-Host "executing $nextFileName" -ForegroundColor DarkMagenta
    #DO EXECUTE FILE    
    Invoke-Sqlcmd -InputFile $nextFileName -ServerInstance $dbServer -Username $dbUser -Password $dbUPwd -Database $dacProfile.TargetDatabaseName -QueryTimeout  65535
        
    $currentDBVersion++
    $targetDBVersion++

    $nextFileName = [string]::Format("{0}\UpgradeScripts\{1}.sql", $ProjectPath,$targetDBVersion.ToString("D4"))
}
Write-Host "Upgrade script execution complete.Current DB Version: $currentDBVersion" -ForegroundColor Cyan

# Release.sql file is a re-runnable collection of scripts that will be introduced ONLY in a release branch in order to fix any 
# core (non client) issues. This file will not be present in the dev branch; however, this may appear in the master branch
[string] $releaseScriptFileName = [string]::Format("{0}\UpgradeScripts\Release.sql", $ProjectPath)
if(Test-Path $releaseScriptFileName){
    Write-Host "Executing Release Script"
    Invoke-Sqlcmd -InputFile $releaseScriptFileName -ServerInstance $dbServer -Username $dbUser -Password $dbUPwd -Database $dacProfile.TargetDatabaseName -QueryTimeout  65535    
}

Write-Host "Building db project" -ForegroundColor DarkGray
#Now build the dbProject to generate the dacpac
$buildExpression = [string]::Format("{0} /t:Rebuild /p:Warn=0 /p:Configuration=Debug '{1}' /nr:false",$msbuild,$projFile.FullName)
Invoke-Expression $buildExpression

Write-Host "Comparing DB and updating Programable Objects" -ForegroundColor DarkGray
$dacpacFile = Get-ChildItem -Path ([string]::Format("{0}\bin\Debug\",$ProjectPath))  -Filter *.dacpac | Select-Object -First 1

#Use the connect string from the profile to initiate the service
$dacService = New-Object Microsoft.SqlServer.dac.dacservices ($dacProfile.TargetConnectionString)
 
#Load the dacpac
$dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($dacpacFile.FullName)

#Publish
try{
    $dacService.deploy($dacPackage, $dacProfile.TargetDatabaseName, $true, $dacProfile.DeployOptions)
    Write-Host "DB Sync Completed" -ForegroundColor Green
}
catch [Microsoft.SqlServer.Dac.DacServicesException]{
    $_ | fl * -Force
}


# exictuting client specific scripts if any
<#  In order to configure a client specific environment and put a syncdb.json file
    {
        "client":{
            "name":"telus"
        }
    }
    Steps to be performed
        1. Check if the file exists. If not skip
        2. Check if the client name in the file matches with the client name in the db.
            2.a. If not, exit with error
            2.b. If no client name configured in the db,
                2.b.1. Insert client db name in the appropriate table
            2.c. Execute the pending scripts from the client specific folder
#>

[string] $syncdbConfigPath = [string]::Format("{0}\syncdb.json", $ProjectPath)
if(Test-Path ($syncdbConfigPath)){
    Write-Host "Executing client specific scripts" -ForegroundColor Green
    $configurationFromFile = Get-Content $syncdbConfigPath | Out-String | ConvertFrom-Json
    $configurationFromDB = Invoke-Sqlcmd -Query "Select * from DBConfig" -ServerInstance $dbServer -Username $dbUser -Password $dbUPwd -Database $dacProfile.TargetDatabaseName -QueryTimeout  65535
    if($configurationFromDB){ #something configured in the db
        if($configurationFromDB.Name -ne $configurationFromFile.client.name){
            Write-Error -Message "Configuration Mismatch: The client name in the database doesn't match with the syncdb.json"            
            exit
        }
    }else{        
        Invoke-Sqlcmd -Query "INSERT INTO DBConfig(Name) VALUES ('$($configurationFromFile.client.name)')" -ServerInstance $dbServer -Username $dbUser -Password $dbUPwd -Database $dacProfile.TargetDatabaseName -QueryTimeout  65535
    }

    #get the current version client specific scripts
    [int]$currentDBVersion = GetCurrentVersion -profileXml $profileXml -clientVersion $True
    [int]$targetDBVersion = $currentDBVersion + 1

    Write-Host "Current Client Script Version: $currentDBVersion" -ForegroundColor Cyan
    Write-Host "Checking for upgrade scripts..." -ForegroundColor DarkGray

    [string] $nextFileName = [string]::Format("{0}\UpgradeScripts\Clients\{2}\{1}.sql", $ProjectPath,$targetDBVersion.ToString("D4"), $configurationFromFile.client.name)
    while(Test-Path $nextFileName){
        Write-Host "executing $nextFileName" -ForegroundColor DarkMagenta
        #DO EXECUTE FILE    
        Invoke-Sqlcmd -InputFile $nextFileName -ServerInstance $dbServer -Username $dbUser -Password $dbUPwd -Database $dacProfile.TargetDatabaseName -QueryTimeout  65535
            
        $currentDBVersion++
        $targetDBVersion++

        $nextFileName = [string]::Format("{0}\UpgradeScripts\Clients\{2}\{1}.sql", $ProjectPath,$targetDBVersion.ToString("D4"), $configurationFromFile.client.name)
    }
    Write-Host "Client specific upgrade script execution complete. Current client script version: $currentDBVersion" -ForegroundColor Cyan

}

Write-Host "Building db project" -ForegroundColor DarkGray
#Now build the dbProject to generate the dacpac
$buildExpression = [string]::Format("{0} /t:Rebuild /p:Warn=0 /p:Configuration=Debug '{1}'",$msbuild,$projFile.FullName)
Invoke-Expression $buildExpression

Write-Host "Comparing DB and updating Programable Objects" -ForegroundColor DarkGray
$dacpacFile = Get-ChildItem -Path ([string]::Format("{0}\bin\Debug\",$ProjectPath))  -Filter *.dacpac | Select-Object -First 1

#Use the connect string from the profile to initiate the service
$dacService = New-Object Microsoft.SqlServer.dac.dacservices ($dacProfile.TargetConnectionString)
 
#Load the dacpac
$dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($dacpacFile.FullName)

#Publish
try{
    $dacService.deploy($dacPackage, $dacProfile.TargetDatabaseName, $true, $dacProfile.DeployOptions)
    Write-Host "DB Sync Completed" -ForegroundColor Green
}
catch [Microsoft.SqlServer.Dac.DacServicesException]{
    $_ | fl * -Force
}