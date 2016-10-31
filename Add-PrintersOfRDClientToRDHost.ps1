<#
  .SYNOPSIS
    Adds all printers that are shared on a RD client to the RD host.
 
   .DESCRIPTION
    Adds all printers that are shared on a RD client to the RD host. If the default printer of the RD client is shared
    its set as default printer on the RD host
 
  .EXAMPLE
    Add-PrintersOfRDClientToRDHost.ps1
#>

[cmdletbinding()]
Param()

<#
  .SYNOPSIS
    Returns the RDS session ID of a given user.
    stolen from: http://www.out-web.net/?p=1479
 
  .DESCRIPTION
    Leverages query.exe session in order to get the given user's session ID.
 
  .EXAMPLE
    Get-RDSSessionId
 
  .EXAMPLE
    Get-RDSSessionId -UserName johndoe
 
  .OUTPUTS
    System.String
#>
function Get-RDSSessionId
{
  [CmdletBinding()]
  Param
  (
  # Identifies a user name (default: current user)
    [Parameter(ValueFromPipeline = $true)]
    [System.String] 
    $UserName = $env:USERNAME
  )
  $returnValue = $null
  try
  {
    $ErrorActionPreference = 'Stop'

    #get the sessions but filter only the current one (the one starting with ">") **changed by Artur Neumann
    #we could also check for the user name here
    $output = query.exe session $UserName |
      ForEach-Object {$_.Trim() -replace '\s+', ','} |
        Where-Object {$_ -like ">*"} |
         ConvertFrom-Csv -Header "SESSIONNAME","USERNAME","ID","STATUS","TYPE","GER"

          
    $returnValue = $output.ID
  }
  catch
  {
    $_.Exception | Write-Error
  }
  New-Object psobject $returnValue
}
 
<#
  .SYNOPSIS
    Returns the RDS client name
    stolen from: http://www.out-web.net/?p=1479
 
  .DESCRIPTION
    Returns the value of HKCU:\Volatile Environment\<SessionID>\CLIENTNAME
 
  .EXAMPLE
    Get-RDSClientName -SessionId 4
 
  .EXAMPLE
    Get-RDSClientName -SessionId Get-RDSSessionId
 
  .OUTPUTS
    System.String
#>
function Get-RDSClientName
{
  [CmdletBinding()]
  Param
  (
  # Identifies a RDS session ID
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [System.String] 
    $SessionId
  )
  $returnValue = $null
  $regKey = 'HKCU:\Volatile Environment\{0}' -f $SessionId
  try
  {
    $ErrorActionPreference = 'Stop'
    $regKeyValues = Get-ItemProperty $regKey
    $sessionName = $regKeyValues | ForEach-Object {$_.SESSIONNAME}
    if ($sessionName -ne 'Console')
    {
      $returnValue = $regKeyValues | ForEach-Object {$_.CLIENTNAME}
    }
    else
    {
      Write-Warning 'Console session'
#     $returnValue = $env:COMPUTERNAME
    }
  }
  catch
  {
    $_.Exception | Write-Error
  }
  New-Object psobject $returnValue
}
 

#find Client computer name
$ClientComputer = Get-RDSSessionId | Get-RDSClientName
Write-Verbose "RD Client name: '$ClientComputer'"

Get-Printer | ? {$_.ComputerName -eq $ClientComputer} | 
    ForEach { 
        
        try {
            Remove-Printer -InputObject $_ -EA Stop
            Write-Verbose "removed printer $($_.Name)"
        } catch {
            Write-Verbose "could not remove printer $($_.Name)"
        }
    }

#Add all shared printers of the Client to the RD host
Get-Printer -ComputerName $ClientComputer | ? {$_.Shared -eq $true} | 
    ForEach {
        Write-Verbose "adding printer: \\$ClientComputer\$($_.Name)"
        Add-Printer -ConnectionName \\$ClientComputer\$($_.Name)
        }


try {
    #find the default printer of the client
    $Reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('currentuser', $ClientComputer)
    $RegKey= $Reg.OpenSubKey('Software\Microsoft\Windows NT\CurrentVersion\Windows')
    $DefaultPrinter = $RegKey.GetValue("Device")
    $DefaultPrinterName = $DefaultPrinter | ConvertFrom-Csv -Header Name, Provider, Order| Select -expand Name
    Write-Verbose "default printer of the current user on the RD client ($ClientComputer) is '$DefaultPrinterName'"
}
catch {
    Write-Error "Cannot determine default printer on the RD client ($ClientComputer). You might have to start the RemoteRegistry Service on the Client"
    Exit
}


try {
    #check if the default printer of the client was also shared
    $DefaultPrinterShareName =Get-Printer -ComputerName $ClientComputer -Name $DefaultPrinterName -Full -ErrorAction Stop| 
        ? {$_.Shared -eq $true} |
        Select -expand ShareName 
}
catch {
    $DefaultPrinterShareName = $false
}



if ($DefaultPrinterShareName) {
    Write-Verbose "default printer on the RD client is shared as '$DefaultPrinterShareName'"
    Write-Verbose "setting '$DefaultPrinterShareName' as default printer on the RD host"

    #find that printer and set it as default
    $printer=Get-WmiObject -Query "Select * From Win32_Printer WHERE ShareName = '$($DefaultPrinterShareName)'"
    $printer.SetDefaultPrinter()  | Out-Null
} 
else {
    Write-Verbose "Default Printer of the RD client is not shared, so we cannot use it on the RD host"
}