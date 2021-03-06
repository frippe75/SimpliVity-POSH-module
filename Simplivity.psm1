##########################################################################
# POSH Wrapper for Simplivity REST API
# Generated by Ron R Dharma, adapted from J Hildebrand's SimpliVity module
# (C) CopyRight 2019 Apache license 2.0
##########################################################################
#
#-----------------------------------------------------------------------------
# GENERAL FUNCTIONS adaptation
# $Rev:: 244           $:  Revision of last commit
# $Author:: rondharma  $:  Author of last commit
# $Date:: 2019-04-01 2#$:  Date of last commit
# -----------------------------------------------------------------------------
#>
<#
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
#>

function Connect-OmniStack {
<#
.SYNOPSIS 
	Obtain the OAuth Token from SimpliVity OVC 
.DESCRIPTION
	Using vCenter Administrator authentication for SimpliVity OmniStack Virtual Controller
.NOTES
	Required parameter: (This will prompt for username and password input)
		-Server <IP Address of OVC>
		-IgnoreCertReqs <Self-signed SSL cert is accepted>
	Not required parameters: (This will bypass the prompt for username and password)
		-OVCusername <OVC username has admin rights to Federation>
		-OVCpassword <OVC password>
		-OVCcred <User generated credential as System.Management.Automation.PSCredential"
.SYNTAX
	PS> Connect-OmniStack -Server <IP Address of OVC>  
	PS> Connect-OmniStack -Server <IP Address of OVC> -OVCusername <username@domain> -OVCpassword <P@55w0rd>
	PS> Connect-OmniStack -Server <IP Address of OVC> -OVCcred <User generated Secure credentials>
.RETURNVALUE
	The Omnistack OAuth:
		{
		    "Server":  "https://10.20.4.161",
		    "Username":  "CLOUD\\Ron.Dharma",
		    "Token":  "31e39218-a2c3-407c-b4bf-7eb9d53e0d08",

		    "SignedCertificates":  false
        }
    The detail of implementation is available in the https://developer.hpe.com/platform/hpe-simplivity/authenticating-against-hpe-omnistack-api
.EXAMPLE
    Tip to use the -OVCcred parameter:

    To generate a credential file that can be used for this API, please use the export-CLIXML and then reimport using import-CLIXML
	$MyCredentials=Get-Credential -Credential"CONTOSO\Username"| export-CLIXML C:\scriptforlder\SecureCredentials.XML
	This SecureCredentials can be read back as long as the import action is being done in the same host as export
	This credentials can then passed as the -OVCcred 
	$MyCredentials=import-CLIXML C:\Scriptfolder\SecureCredentials.xml
#>
    [CmdletBinding()][OutputType('System.Management.Automation.PSObject')]

    param(
        [parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [ValidateNotNullOrEmpty()]
        [String]$Server,

        [parameter(Mandatory = $false)]
        [switch]$IgnoreCertReqs,
        [String]$OVCusername,
        [String]$OVCpassword,
        [System.Management.Automation.PSCredential]$OVCcred
    )

    if ($IgnoreCertReqs.IsPresent) {
       	if ( -not ("TrustAllCertsPolicy" -as [type])) {
            Add-Type @"
            using System.Net;
            using System.Security.Cryptography.X509Certificates;
            public class TrustAllCertsPolicy : ICertificatePolicy
            {
                public bool CheckValidationResult(
                    ServicePoint srvPoint, X509Certificate certificate,
                    WebRequest request, int certificateProblem)
                    {  return true; }
            }
"@
        }
    
        [System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
        [System.Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $SignedCertificates = $false
    }
    else { 
        $SignedCertificates = $true 
    }

    # Check if IP Address is a valid one
    $IsValid = ($Server -as [Net.IPAddress]) -as [Bool]
    If ( $IsValid -eq $false ) {
        Write-Error "$Server has invalid IP Address, please provide valid IP Address!"
        Break
    }

    # Allow any of three authentication parameters in this priority: $cred object, cleartext cred, and no credential at all.
    if ($OVCcred) {
        $cred = $OVCcred
    }
    elseif (($OVCusername) -and ($OVCpassword)) {	
        $secPasswd = ConvertTo-SecureString $OVCpassword -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($OVCusername, $secPasswd)
    }
    else {
        $cred = $host.ui.PromptForCredential("Enter in your OmniStack Credentials", "Enter in your username & password.", "", "")
    }
    $username = $cred.UserName
    $pass_word = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password))
    $uri = "https://" + $Server + "/api/oauth/token"
    $base64 = [Convert]::ToBase64String([System.Text.UTF8Encoding]::UTF8.GetBytes("simplivity:"))
    $body = @{username = "$username"; password = "$pass_word"; grant_type = "password"}
    $headers = @{}
    $headers.Add("Authorization", "Basic $base64")
    $headers.Add("Accept", "application/json")
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Body $body -Method Post
    }
    catch {
        Write-Error $_.Exception.Message
        if ($_.Exception.Response.STatusCode.value__) {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $reader.BaseStream.Position = 0
            return $reader.ReadToEnd()	
        }
        exit
    } 
    $Global:OmniStackConnection = [pscustomobject]@{
        Server             = "https://$($Server)"
        OVCcred            = $cred
        Token              = $response.access_token
        UpdateTime         = $response.updated_at
        Expiration         = $response.expires_in
        SignedCertificates = $SignedCertificates
    }
    $OmniStackConnection
}

function Invoke-OmnistackREST {
<#  
.SYNOPSIS 
	Execute REST API call using Powershell Invoke-RestMethod  
.DESCRIPTION
	The token for authorization will automatically reacquired when needed
.NOTES
	Required parameter: URI, headers, methods, body
.SYNTAX
	This function is internal functions.
.RETURNVALUE
	Status of execution.
.EXAMPLE
#>
    [CmdletBinding()] [OutputType('System.Management.Automation.PSObject')]
    param(
        [parameter(Mandatory = $True)]
        [ValidateNotNullOrEmpty()]
        [System.Object]$uri,
        [System.Collections.IDictionary]$header,
        [string]$Method,
        [parameter(Mandatory = $false)]
        [System.object]$body
    )

    $headers = @{}
    $headers.Add("Authorization", "Bearer $($Global:OmniStackConnection.Token)")
    $headers.Add("Accept", "application/json")

    # Allow added headers to be passed 
    if ($header) {
	$headers.Add($header)
    }

    try {
        # Invoke REST API method
        $local_response = Invoke-RestMethod -Uri $($Global:OmniStackConnection.Server) + $uri -Headers $headers -Body $body -Method $Method
	} 
	catch {
        if ($_.Exception.Message -match "401") {   
            # If there is exception and the REST API status = 401, perform the re-authentication and obtain new access token
            $local_cred = $Global:OmnistackConnection.OVCcred
            $local_username = $local_cred.UserName
            $local_Passwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($local_cred.Password))
            $local_uri = $($Global:OmniStackConnection.Server) + "/api/oauth/token"
            $local_body = @{username = "$local_username"; password = "$local_Passwd"; grant_type = "password"}
            $local_base64 = [Convert]::ToBase64String([System.Text.UTF8Encoding]::UTF8.GetBytes("simplivity:"))
            $local_headers = @{}
            $local_headers.Add("Authorization", "Basic $local_base64")
            $local_headers.Add("Accept", "application/json")
            $local_response = Invoke-RestMethod -Uri $local_uri -Headers $local_headers -Body $local_body -Method Post
            $Global:OmnistackConnection.Token = $local_response.access_token
            $header.Remove("Authorization")
            $header.Add("Authorization", "Bearer $($Global:OmniStackConnection.Token)")
            $local_response = Invoke-RestMethod -Uri $uri -Headers $headers -Body $body -Method $Method
        }
        else {
            # If the exception is other than 4XX then returns the status accordingly
            Write-Host -ForegroundColor Red $_.Exception.Message
            if ($_.Exception.Response.STatusCode.value__) {
                $local_stream = $_.Exception.Response.GetResponseStream()
                $local_reader = New-Object System.IO.StreamReader($local_stream)
                $local_reader.BaseStream.Position = 0
                $local_response = $local_reader.ReadToEnd() | convertfrom-json
            }
        }
    }
    # For Method other than GET, perform the Task query to ensure Task completion prior to returning good status
    if ($Method -match "[Pp]ost" -or $Method -match "[Dd]elete") {
        if (($_.Exception.Message -match "4[0-9][0-9]") -or ($local_response.task -eq $NULL) ) { 
            Write-Debug "Failed POST or DELETE" 
            return $local_response
        }
        else {
            do {
                $Task_response = Get-OmniStackTask $local_response.task
                Write-Debug $Task_response.task.state
                Start-Sleep -Milliseconds 500
            } 	until ($Task_response.task.state -notmatch "IN_PROGRESS")
            return $Task_response
        }
    }
    else {
        return $local_response
    }
}

function Redo-OmniStackToken {
<#
.SYNOPSIS 
	Obtain the access token using the refresh token after it's expired
.DESCRIPTION
	Internal function for the error handling of the REST API feature function call
.NOTES
	Required parameter: None
    Required Variable: $OmniStackConnection.Token; $OmniStackConnection.Refresh
    SimpliVity token expiration 10 minutes inactivity or 24 hours
.SYNTAX
    Redo-OmniStackToken
.RETURNVALUE
    OmnistackConnection with the new token
#>

    # Old way before 3.6.1: use the refresh token to obtain the access token after 10 min inactivity timeout
    # $Local:uri = $($Global:OmniStackConnection.Server) + "/api/oauth/token"
    # $Local:body = @{grant_type="refresh_token";refresh_token="$($Global:OmniStackConnection.Refresh)"}
    # $base64 = [Convert]::ToBase64String([System.Text.UTF8Encoding]::UTF8.GetBytes("simplivity:"))
    # $Local:headers = @{}
    # $Local:headers.Add("Authorization", "Basic $base64")
    # $Local:headers.Add("Accept", "application/json")

    $cred = $Global:OmniStackConnection.OVCcred
    $username = $cred.UserName
    $Passwd = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($cred.Password))
    $uri = "https://" + $Server + "/api/oauth/token"
    $base64 = [Convert]::ToBase64String([System.Text.UTF8Encoding]::UTF8.GetBytes("simplivity:"))
    $body = @{username = "$username"; password = "$Passwd"; grant_type = "password"}
    $headers = @{}
    $headers.Add("Authorization", "Basic $base64")
    $headers.Add("Accept", "application/json")
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Body $body -Method Post
    $Global:OmniStackConnection.Token = $response.access_token
    $OmniStackConnection
}
<#
--------------------------------------------------------------------------------
CLUSTER FUNCTIONS
--------------------------------------------------------------------------------
#>
function Get-OmnistackCluster {
<#
.SYNOPSIS 
	Obtain Cluster information from SimpliVity federation.
.DESCRIPTION
	SimpliVity Cluster ID represents the Fault Domain as shown in svt-federation-show
.NOTES
    Required parameter: None
    Available parameters: 
    -ClusterID to select a Cluster and returns all the members
    -No ClusterID to return all clusters available
.SYNTAX
    Get-OmnistackCluster 
.RETURNVALUE
    OmnistackConnection with the new token
#>
    [CmdletBinding()][OutputType('System.Management.Automation.PSObject')]
    param(
        [parameter(Mandatory = $false)]
        [switch]$ShowOptionalFields,
        [string]$ClustertLimit,
        [string]$ClusterOffset,
        [string]$ClusterId,
        [string]$ClusterFields,
        [string]$SortField,
        [string]$SortOrder
    )
    if ($PSBoundParameters.ContainsKey("ShowOptionalFields")) {
        $ShowOption = "?show_optional_fields=true"
    }
    else {
        $ShowOption = "?show_optional_fields=false"
    }
    if ($ClusterID.length -gt 1) {
        $uri = "/api/omnistack_clusters/" + "$ClusterID"
    }
    else {
        $uri = "/api/omnistack_clusters" + "$ShowOption"
    }
    $body = $null
    $response = Invoke-OmnistackREST -uri $uri -body $body -Method Get
    $response
}

<#
-----------------------------------------------------------------------------
VIRTUAL MACHINE FUNCTIONS
-----------------------------------------------------------------------------
#>

function Get-OmniStackVM {
<#
.SYNOPSIS 
	Obtain the VM list from SimpliVity federation
.DESCRIPTION
	All of VM that are part of a designated SimpliVity Federation
.NOTES
    Required parameter: None
    Available parameters: 
    -ClusterID to select a Cluster and returns all the members
    -No ClusterID to return all clusters available
.SYNTAX
    Get-OmnistackCluster 
.RETURNVALUE
    OmnistackConnection with the new token
#>
    [CmdletBinding()][OutputType('System.Management.Automation.PSObject')]
    param(
        [Parameter(Mandatory = $false, Position = 1, ValueFromPipeline = $True)]
        [ValidateNotNullOrEmpty()]
        [string]$VMid,
        [Parameter(Mandatory = $false)]
        [ValidateNotNullOrEmpty()]
        [string]$VMname,
        [parameter(Mandatory = $false)]
        [switch]$ShowOptionalFields,
        [string]$VMListLimit,
        [string]$VMListOffset,
        [string]$DSid
    )
	
    if ([string]::IsNullOrEmpty($VMid)) {
        $uri = "/api/virtual_machines"
    }
    else {
        $uri = "/api/virtual_machines/" + $VMid
    }

    $body = @{}
    if ($PSBoundParameters.ContainsKey("ShowOptionalFields")) {
        $body.Add("show_optional_fields", "true")
    }
    else {
        $body.Add("show_optional_fields", "false")
    }
    $body.Add("name", $VMname)
    $body.Add("limit", $VMListLimit)
    $body.Add("offset", $VMListOffset)
    $body.Add("datastore_id", $DSid)
    $response = Invoke-OmnistackREST -uri $uri -body $body -Method Get
    $response
}

function Copy-OmniStackVM {
<#
.SYNOPSIS 
	HPE OmniStack Fast Clone of VM
.DESCRIPTION
	Using SimpliVity OVC 
.NOTES
.SYNTAX
	Copy-OmnistackVM -VM <VMinstance> -Name <VM clone>
.RETURNVALUE
	The status of Invoke-OmnistackRest
.EXAMPLE
	$a = Copy-OmniStackVM -VM $originalVM -Name "ClonedOfVM"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [psobject]$VM,
        [Parameter(Mandatory = $true, ParameterSetName = "Name")]
        [string]$Name
    )

    $uri = "/api/virtual_machines/" + $($VM.ID) + "/clone"
    $body = @{}
    $body.Add("app_consistent", "false")
    $body.Add("virtual_machine_name", "$Name")
    $body = $body | ConvertTo-Json
    $response = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
    return $response
}

function Move-OmniStackVM {
<#
.SYNOPSIS 
	HPE OmniStack Transfer of VM from one cluster to another cluster
.DESCRIPTION
	Using SimpliVity OVC 
.NOTES
.SYNTAX
	Move-OmnistackVM -VM <VMinstance> -MovedVMNAme <Name of the VM at the destination> -DestinationDatastore <Datastore ID>
.RETURNVALUE
	The status of Invoke-OmnistackRest
.EXAMPLE
	$a = Move-OmniStackVM -VM "AVM" -Name  "BVM" -Datastore 23415..234
#>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$VM,
        [Parameter(Mandatory = $true)]
        [string]$MovedVMName,
        [Parameter(Mandatory = $true)]
        [string]$DestinationDatastore
    )

    $DestinationDSid = (Get-OmniStackDatastore).datastores | Where-Object {$_.Name -eq $DestinationDatastore} | 
        Select-Object -ExpandProperty id

    $uri = "/api/virtual_machines/" + $($VM.ID) + "/move"
    $body = @{}
    $body.Add("virtual_machine_name", "$MovedVMName")
    $body.Add("destination_datastore_id", "$DestinationDSid")
    $body = $body | ConvertTo-Json
    $response = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
    return $response
}

function Set-OmniStackVMPolicy {
<#
.SYNOPSIS 
	HPE OmniStack Set OmniStack Backup Policy for VM and DataStore
.DESCRIPTION
	Using SimpliVity OVC 
.NOTES
.SYNTAX
	Copy-OmnistackVM -VM <VMinstance> -PolicyID <Policy ID >
.RETURNVALUE
	The status of Invoke-OmnistackRest
.EXAMPLE
	$a = Copy-OmniStackVM -VM $originalVM -Name "ClonedOfVM"
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [psobject]$VM,
        [Parameter(Mandatory = $true)]
        [string]$PolicyId
    )

    $uri = "/api/virtual_machines/" + $($VM.ID) + "/set_policy"
       $body = @{}
    $body.Add("policy_id", "$PolicyId")
    $body = $body | ConvertTo-Json
    $response = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
    return $response
}
<#
-----------------------------------------------------------------------------
DATASTORE FUNCTIONS
-----------------------------------------------------------------------------
#>

function Get-OmniStackDatastore {
    <#
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 1, ValueFromPipeline = $True)]
        [string]$DataStoreID,
        [Parameter(Mandatory = $false, Position = 2)]
        [int]$DSListOffset = 0,
        [Parameter(Mandatory = $false, Position = 3)]
        [int]$DSListLimit = 500
    )
	
    process {
        if ([string]::IsNullOrEmpty($DataStoreID)) {
            $uri = "/api/datastores"
        }
        else {
            $uri = "/api/datastores/" + $DataStoreID
        }
        $body = @{}
        $body.Add("limit", $DSListLimit)
        $body.Add("offset", $DSListOffset)
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Get
        return $result
    }
}
function New-OmnistackDatastore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$DSname,
        [Parameter(Mandatory = $true)]
        [string]$ClusterId,
        [string]$PolicyId,
        [Double]$DSsize
    )
	
    process {
        $uri = "/api/datastores"
        $body = @{}
        $body.Add("name", "$DSname")
        $body.Add("omnistack_cluster_id", "$ClusterId")
        $body.Add("policy_id", "$PolicyId")
        $body.Add("size", "$DSsize")
        $body = $body | ConvertTo-Json
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
        return $result
    }
}

function Remove-OmnistackDatastore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$DatastoreID
    )
	
    process {
        $uri = "/api/datastores/" + $DatastoreID
        $body = @{}
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Delete
        return $result	
    }
}

function Resize-OmnistackDatastore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$DatastoreID,
        [Parameter(Mandatory = $true)]
        [double]$DSsize
    )
	
    process {
        $SizeString = [string] $DSsize
        $uri = "/api/datastores/" + $DatastoreID + "/resize"
        $body = @{}
        $body.Add("size", "$SizeString")
        $body = $body | ConvertTo-Json
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
        return $result	
    }
}
function Set-OmnistackDatastorePolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$DatastoreID,
        [Parameter(Mandatory = $true)]
        [string]$DSpolicy
    )
	
    process {
        $uri = "/api/datastores/" + $DatastoreID + "/set_policy"
        $body = @{}
        $body.Add("policy_id", "$DSpolicy")
        $body = $body | ConvertTo-Json
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
        return $result	
    }
}

function Remove-OmnistackDatastoreShare {
	[CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$DatastoreID,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$StandardHostName

	)
	process {
		$uri = "/api/datastores/" + $DatastoreID + "/unshare"
		$body = @{}
		$body.Add("host_name", "$StandardHostName")
		$body = $body | ConvertTo-Json
		$result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
		return $result
	}

}

function Set-OmnistackDatastoreShare {
	[CmdletBinding()]
    	param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$DatastoreID,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$StandardHostName

	)
	process {
		$uri = "/api/datastores/" + $DatastoreID + "/share"
		$body = @{}
		$body.Add("host_name", "$StandardHostName")
		$body = $body | ConvertTo-Json
		$result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
		return $result
	}

}

function Get-OmnistackDatastoreStandardHost {
	[CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$DatastoreID
	)
	process {
		$uri = "/api/datastores/" + $DatastoreID + "/standard_hosts"
		$body = @{}
		$result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Get
		return $result
	}

}

<#
-----------------------------------------------------------------------------
TASK FUNCTIONS
-----------------------------------------------------------------------------
#>
function Get-OmniStackTask {
    <#
.SYNOPSIS 
	Pooling for completion of the REST API operation
.DESCRIPTION
	External function for polling completion of REST API
.NOTES
	Required parameter: TaskID.ID
	Required Variable: $OmniStackConnection.Token
.SYNTAX
	Get-OmniStackTask
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [psobject]$Task
    )

    $uri = "/api/tasks/" + $($Task.ID)
    $body = @{}
    $response = Invoke-OmnistackREST -uri $uri -body $body -Method Get
    return $response
}


<# 
--------------------------------------------------------------------------------
BACKUP FUNCTIONS
--------------------------------------------------------------------------------
#>

function Get-OmnistackBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, Position = 1, ValueFromPipeline = $True)]
        [string]$BackupID,
        [Parameter(Mandatory = $false, Position = 2)]
        [int]$BackupOffset = 0,
        [Parameter(Mandatory = $false, Position = 3)]
        [int]$BackupLimit = 500,
        [Parameter(Mandatory = $false)]
        [string]$VMid
    )
	
    process {
        if ([string]::IsNullOrEmpty($BackupID)) {
            $uri = "/api/backups"
        }
        else {
            $uri = "/api/backups/" + $BackupID
        }
        $body = @{}
        $body.Add("limit", $BackupLimit)
        $body.Add("offset", $BackupOffset)
        if (-not [string]::IsNullOrEmpty($VMid)) {
            $body.Add("virtual_machine_id", $VMid)
        }
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Get
        return $result	
    }
}

function Remove-OmnistackBackupLegacy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$BackupID
    )
    process {
        $uri = "/api/backups/" + $BackupID
        $body = @{}
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method 'Delete'
        return $result	
    }
}

function Remove-OmnistackBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [String[]]$BackupIDs
    )
    process {
        $uri = "/api/backups/delete"
        $body = @{}
        $body.Add("backup_id", $BackupIDs)
        $body = ConvertTo-Json -InputObject $body
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method POST
        return $result	
    }
}

function Restore-OmnistackBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 1, ValueFromPipeline = $True)]
        [string]$BackupID,
        [Parameter(Mandatory = $true, Position = 2)]
        [string]$DataStoreID,
        [Parameter(Mandatory = $false, Position = 3)]
        [string]$RestoredVMname = "",
        [Parameter(Mandatory = $false)]
        [switch]$restore_original
    )
    Process {
        if ($PSBoundParameters.ContainsKey("restore_original")) {
            $originalKey = "?restore_original=TRUE"
        }
        else {
            $originalKey = "?restore_original=FALSE"
        }
        $uri = "/api/backups/" + $BackupID + "/restore" + $originalKey
        $body = @{}
        $body.Add("virtual_machine_name", $RestoredVMname)
        $body.Add("datastore_id", $DataStoreID)
        $body = ConvertTo-Json -InputObject $body
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method POST
        return $result	
    }

}
<# 
--------------------------------------------------------------------------------
BACKUP POLICY FUNCTIONS
--------------------------------------------------------------------------------
#>
function Get-OmnistackBackupPolicy {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 1)]
        [int]$PolicyOffset = 0,
        [Parameter(Mandatory = $false, Position = 2)]
        [int]$PolicyLimit = 500,
        [Parameter(ValueFromPipeline = $true)]
        [string]$policyid,
        [Parameter(Mandatory = $false)]
        [switch]$Short
    )
    process {
        if ([string]::IsNullOrEmpty($policyId)) {
            $uri = "/api/policies"
        }
        else {
            $uri = "/api/policies/" + $policyId
        }
        $body = @{}
        $body.Add("limit", $PolicyLimit)
        $body.Add("offset", $PolicyOffset)
        if ($Short.IsPresent) {
            $body.Add("fields", "name, id")
            $body.Add("sort", "name")
            $body.Add("order", "ascending")
        }
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Get
        return $result
    }
}

function Get-OmnistackPolicyRule() {
    [CmdletBinding()]
    param(
        [Parameter(mandatory = $true, ValueFromPipeline = $true)]
        [string]$policyid,
        [string]$ruleID
    )
	
    process {
        $uri = "/api/policies/" + $policyid + "/rules/" + $ruleID
        $body = @{}
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Get
        $result
    }
}

function Get-OmnistackPolicyDatastore() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$policyid
    )
	
    process {
        $uri = "/api/policies/" + $policyid + "/datastores"
        $body = @{}
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Get
        $result
    }
}

function Get-OmnistackPolicyVM() {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string]$policyID
    )
	
    process {
        $uri = "/api/policies/" + $policyid + "/virtual_machines"
        $body = @{}
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Get
        $result
    }
}

function New-OmnistackPolicy() {
<#
.SYNOPSIS
OmniStack REST API call to setup Policy

.DESCRIPTION
Establishing Backup Policy for OmniStack 

.PARAMETER policyName
This is the Name of this New Policy

.EXAMPLE
An example

.NOTES
General notes
#>
    [CmdletBinding()]
    param(
        [Parameter(	mandatory = $true, ValueFromPipeline = $true, position = 1)] 
        [string]$policyName
    )

    process {
        $uri = "/api/policies/"
        $body = @{}
        $body.Add("name", "$policyName")
        $body = $body | ConvertTo-Json
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
        $result
    }
}

function New-OmnistackRule() {
    <#
.SYNOPSIS
OmniStack REST API to establish Omnistack Backup rule under one particular policy

.DESCRIPTION
Required to establish the content of Backup Policy

.PARAMETER policyID
Parameter description

.PARAMETER DestinationClusterId
Parameter description

.PARAMETER EndTime
Parameter description

.PARAMETER StartTime
Parameter description

.PARAMETER Frequency
Parameter description

.PARAMETER Retention
Parameter description

.PARAMETER Days
Parameter description

.PARAMETER Replace
Parameter description

.PARAMETER AppConsistent
Parameter description

.EXAMPLE
An example

.NOTES
General notes
#>
    [CmdletBinding()]
    param(
        [Parameter(mandatory = $true, ValueFromPipeline = $true, position = 1)]
        [string]$policyID,
        [Parameter(mandatory = $true)]
        [string]$DestinationClusterId,
        [string]$EndTime,
        [string]$StartTime,
        [int]$Frequency,
        [int]$Retention,
        [Parameter(mandatory = $false)]
        [string]$Days = "All",
        [bool]$Replace = $false,
        [bool]$AppConsistent = $false
    )

    process {
        $uri = "/api/policies/" + $policyid + "/rules?replace_all_rules=" + $Replace
        $body = @{}
        $body.Add("application_consistent", $AppConsistent)
        $body.Add("days", "$Days")
        $body.Add("destination_id", "$DestinationClusterId")
        $body.Add("end_time", "$EndTime")
        $body.Add("frequency", $Frequency)
        $body.Add("retention", $Retention)
        $body.Add("start_time", "$StartTime")
        $body = ConvertTo-Json -InputObject @($body)
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Post
        $result
    }
}

function Remove-OmnistackRule() {
    [CmdletBinding()]
    param(
        [Parameter(mandatory = $true)]
        [string]$policyid,
        [string]$ruleid
    )
	
    process {
        $uri = "/api/policies/" + $policyid + "/rules/" + $ruleid
        $body = @{}
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Delete
        return $result
    }
}

function Remove-OmnistackPolicy() {
    param(
        [Parameter(ValueFromPipeline = $true)]
        [string]$policyid
    )
		
    process {
        $uri = "/api/policies/" + $policyid 
        $body = @{}
        $result = Invoke-OmnistackREST -Uri $uri -Body $body -Method Delete
        return $result			

    }
}
