# Copyright (c) Anatoliy Ivashina. All rights reserved.
#
# SetDagServerMaintenance.ps1

<#
.Synopsis
   Short description
.DESCRIPTION
   Long description
.EXAMPLE
   Example of how to use this cmdlet
.EXAMPLE
   Another example of how to use this cmdlet
#>

function Set-DagServerMaintenance {
    [CmdletBinding()]

    Param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Start", "Stop", "Check")]
        [string]
        $Maintenance,

        [Parameter(Mandatory = $false)]
        [string]
        $Server = $env:COMPUTERNAME,

        [Parameter(Mandatory = $false)]
        [string]
        $DAG = "A-DAG"
    )

    Begin {
        try {
            # Load the Exchange snapin if it's no already present.
            if (! (Get-PSSnapin Microsoft.Exchange.Management.PowerShell.E2010 -ErrorAction:SilentlyContinue) ) {
                Add-PSSnapin Microsoft.Exchange.Management.PowerShell.E2010 -ErrorAction:Stop
            }

            $RedirectServer = (Get-ExchangeServer | Where-Object { $_.Name -ne $Server } | Select-Object -First 1).Fqdn.ToString()

        }
        catch {
            Break
        }

    }
    Process {
        try {
            switch ($Maintenance) {
                "Start" {
                    Set-ServerComponentState $Server -Component HubTransport -State Draining -Requester Maintenance -Confirm:$false
                    Restart-Service MSExchangeTransport -Force -Confirm:$false
                    Set-ServerComponentState $Server -Component UMCallRouter -State Draining -Requester Maintenance -Confirm:$false
                    Redirect-Message -Server $Server -Target $RedirectServer -Confirm:$false
                    Suspend-ClusterNode $Server -Confirm:$false
                    Set-MailboxServer $Server -DatabaseCopyActivationDisabledAndMoveNow $True -Confirm:$false
                    Set-MailboxServer $Server -DatabaseCopyAutoActivationPolicy Blocked -Confirm:$false
                    Set-ServerComponentState $Server -Component ServerWideOffline -State Inactive -Requester Maintenance -Confirm:$false
                    & "$exscripts\StartDagServerMaintenance.ps1" -serverName $Server -overrideMinimumTwoCopies:$true -Force:$true
                }
                "Stop" {
                    Set-ServerComponentState $Server -Component ServerWideOffline -State Active -Requester Maintenance -Confirm:$false
                    Set-ServerComponentState $Server -Component UMCallRouter -State Active -Requester Maintenance -Confirm:$false
                    Resume-ClusterNode $Server
                    Set-MailboxServer $Server -DatabaseCopyActivationDisabledAndMoveNow $False -Confirm:$false
                    Set-MailboxServer $Server -DatabaseCopyAutoActivationPolicy Unrestricted -Confirm:$false
                    Set-ServerComponentState $Server -Component HubTransport -State Active -Requester Maintenance -Confirm:$false
                    Restart-Service MSExchangeTransport -Confirm:$false
                    & "$exscripts\StopDagServerMaintenance.ps1" -serverName $Server -setDatabaseCopyActivationDisabledAndMoveNow:$false
                    # & "$exscripts\RedistributeActiveDatabases.ps1" -DagName $DAG -BalanceDbsByActivationPreference -Confirm:$false
                }
                "Check" {
                    Get-ServerComponentState $Server | Format-Table Component, State -Autosize
                    Get-MailboxServer $Server | Format-Table Name, DatabaseCopyAutoActivationPolicy -AutoSize
                    Get-MailboxDatabaseCopyStatus -Server $Server | Sort-Object Name | Format-Table -AutoSize
                    Get-ClusterNode $Server | Format-Table -AutoSize
                    Get-Queue -Server $Server | Format-Table -AutoSize
                }
                Default {}
            }
        }
        catch {
            $ErrorMessage = $_.Exception.Message
            $FailedItem = $_.Exception.ItemName
            Break
        }
    }
    End {
        "{0}`n{1}" -f $ErrorMessage, $FailedItem
    }
}

