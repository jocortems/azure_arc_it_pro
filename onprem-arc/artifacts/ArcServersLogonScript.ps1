$ErrorActionPreference = $env:ErrorActionPreference

$Env:ArcBoxDir = "C:\ArcBox"
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$Env:ArcBoxVMDir = "F:\Virtual Machines"
$Env:ArcBoxDscDir = "$Env:ArcBoxDir\DSC"
$agentScript = "$Env:ArcBoxDir\agentScript"

# Moved VHD storage account details here to keep only in place to prevent duplicates.
$vhdSourceFolder = "https://jumpstartprodsg.blob.core.windows.net/arcbox/prod/*"

# Archive existing log file and create new one
$logFilePath = "$Env:ArcBoxLogsDir\ArcServersLogonScript.log"
if (Test-Path $logFilePath) {
    $archivefile = "$Env:ArcBoxLogsDir\ArcServersLogonScript-" + (Get-Date -Format "yyyyMMddHHmmss")
    Rename-Item -Path $logFilePath -NewName $archivefile -Force
}

Start-Transcript -Path $logFilePath -Force -ErrorAction SilentlyContinue

# Remove registry keys that are used to automatically logon the user (only used for first-time setup)
$registryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"
$keys = @("AutoAdminLogon", "DefaultUserName", "DefaultPassword")

foreach ($key in $keys) {
    try {
        $property = Get-ItemProperty -Path $registryPath -Name $key -ErrorAction Stop
        Remove-ItemProperty -Path $registryPath -Name $key
        Write-Host "Removed registry key that are used to automatically logon the user: $key"
    } catch {
        Write-Verbose "Key $key does not exist."
    }
}

# Create Windows Terminal desktop shortcut
$WshShell = New-Object -comObject WScript.Shell
$WinTerminalPath = (Get-ChildItem "C:\Program Files\WindowsApps" -Recurse | Where-Object { $_.name -eq "wt.exe" }).FullName
$Shortcut = $WshShell.CreateShortcut("$Env:USERPROFILE\Desktop\Windows Terminal.lnk")
$Shortcut.TargetPath = $WinTerminalPath
$shortcut.WindowStyle = 3
$shortcut.Save()

# Create desktop shortcut for Logs-folder
$WshShell = New-Object -comObject WScript.Shell
$LogsPath = "C:\ArcBox\Logs"
$Shortcut = $WshShell.CreateShortcut("$Env:USERPROFILE\Desktop\Logs.lnk")
$Shortcut.TargetPath = $LogsPath
$shortcut.WindowStyle = 3
$shortcut.Save()

# Configure Windows Terminal as the default terminal application
$registryPath = "HKCU:\Console\%%Startup"

if (Test-Path $registryPath) {
    Set-ItemProperty -Path $registryPath -Name "DelegationConsole" -Value "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}"
    Set-ItemProperty -Path $registryPath -Name "DelegationTerminal" -Value "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}"
} else {
    New-Item -Path $registryPath -Force | Out-Null
    Set-ItemProperty -Path $registryPath -Name "DelegationConsole" -Value "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}"
    Set-ItemProperty -Path $registryPath -Name "DelegationTerminal" -Value "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}"
}


################################################
# Setup Hyper-V server before deploying VMs for each flavor
################################################
    # Install and configure DHCP service (used by Hyper-V nested VMs)
    Write-Host "Configuring DHCP Service"
    $dnsClient = Get-DnsClient | Where-Object { $_.InterfaceAlias -eq "Ethernet" }
    $dhcpScope = Get-DhcpServerv4Scope
    if ($dhcpScope.Name -ne "ArcBox") {
        Add-DhcpServerv4Scope -Name "ArcBox" `
            -StartRange 10.10.1.100 `
            -EndRange 10.10.1.200 `
            -SubnetMask 255.255.255.0 `
            -LeaseDuration 1.00:00:00 `
            -State Active
    }

    $dhcpOptions = Get-DhcpServerv4OptionValue
    if ($dhcpOptions.Count -lt 3) {
        Set-DhcpServerv4OptionValue -ComputerName localhost `
            -DnsDomain $dnsClient.ConnectionSpecificSuffix `
            -DnsServer 168.63.129.16, 10.16.2.100 `
            -Router 10.10.1.1 `
            -Force
    }


    # Create the NAT network
    Write-Host "Creating Internal NAT"
    $natName = "InternalNat"
    $netNat = Get-NetNat
    if ($netNat.Name -ne $natName) {
        New-NetNat -Name $natName -InternalIPInterfaceAddressPrefix 10.10.1.0/24
    }

    Write-Host "Creating VM Credentials"
    # Hard-coded username and password for the nested VMs
    $nestedWindowsUsername = "Administrator"
    $nestedWindowsPassword = "JS123!!"

    # Create Windows credential object
    $secWindowsPassword = ConvertTo-SecureString $nestedWindowsPassword -AsPlainText -Force
    $winCreds = New-Object System.Management.Automation.PSCredential ($nestedWindowsUsername, $secWindowsPassword)

    # Creating Hyper-V Manager desktop shortcut
    Write-Host "Creating Hyper-V Shortcut"
    Copy-Item -Path "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Administrative Tools\Hyper-V Manager.lnk" -Destination "C:\Users\All Users\Desktop" -Force

    $cliDir = New-Item -Path "$Env:ArcBoxDir\.cli\" -Name ".servers" -ItemType Directory -Force
    if (-not $($cliDir.Parent.Attributes.HasFlag([System.IO.FileAttributes]::Hidden))) {
        $folder = Get-Item $cliDir.Parent.FullName -ErrorAction SilentlyContinue
        $folder.Attributes += [System.IO.FileAttributes]::Hidden
    }


    $vhdImageToDownload = "ArcBox-SQL-ENT.vhdx"

    Write-Host "Fetching SQL VM"
    $SQLvmName = "$namingPrefix-SQL"
    $SQLvmvhdPath = "$Env:ArcBoxVMDir\$namingPrefix-SQL.vhdx"

    # Verify if VHD files already downloaded especially when re-running this script
    if (!(Test-Path $SQLvmvhdPath)) {
        Write-Output "Downloading nested VMs VHDX file for SQL. This can take some time, hold tight..."
        azcopy cp $vhdSourceFolder $Env:ArcBoxVMDir --include-pattern "$vhdImageToDownload" --recursive=true --check-length=false --log-level=ERROR

        # Rename VHD file
        Rename-Item -Path "$Env:ArcBoxVMDir\$vhdImageToDownload" -NewName  $SQLvmvhdPath -Force
    }

    # Create the nested VMs if not already created
    Write-Header "Create Hyper-V VMs"

    # Create the nested SQL VMs
    $sqlDscConfigurationFile = "$Env:ArcBoxDscDir\virtual_machines_sql.dsc.yml"
    (Get-Content -Path $sqlDscConfigurationFile) -replace 'namingPrefixStage', $namingPrefix | Set-Content -Path $sqlDscConfigurationFile
    winget configure --file C:\ArcBox\DSC\virtual_machines_sql.dsc.yml --accept-configuration-agreements --disable-interactivity

    # Restarting Windows VM Network Adapters
    Write-Host "Restarting Network Adapters"
    Start-Sleep -Seconds 5
    Invoke-Command -VMName $SQLvmName -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCreds
    Start-Sleep -Seconds 20

    # Rename server if hostname is not as ArcBox-SQL or doesn't match naming prefix
    $hostname = Invoke-Command -VMName $SQLvmName -ScriptBlock { hostname } -Credential $winCreds

    if ($hostname -ne $SQLvmName) {

        Write-Header "Renaming the nested SQL VM"
        Invoke-Command -VMName $SQLvmName -ScriptBlock { Rename-Computer -NewName $using:SQLvmName -Restart} -Credential $winCreds

        Get-VM *SQL* | Wait-VM -For IPAddress

        Write-Host "Waiting for the nested Windows SQL VM to come back online...waiting for 30 seconds"
        Start-Sleep -Seconds 30

        # Wait for VM to start again
        while ((Get-VM -vmName $SQLvmName).State -ne 'Running') {
            Write-Host "Waiting for VM to start..."
            Start-Sleep -Seconds 5
        }

        Write-Host "VM has rebooted successfully!"
    }

    # Enable Windows Firewall rule for SQL Server
    Invoke-Command -VMName $SQLvmName -ScriptBlock { New-NetFirewallRule -DisplayName "Allow SQL Server TCP 1433" -Direction Inbound -Protocol TCP -LocalPort 1433 -Action Allow } -Credential $winCreds

    # Download SQL assessment preparation script
    Invoke-WebRequest ($Env:templateBaseUrl + "artifacts/prepareSqlServerForAssessment.ps1") -OutFile $nestedVMArcBoxDir\prepareSqlServerForAssessment.ps1
    Copy-VMFile $SQLvmName -SourcePath "$Env:ArcBoxDir\prepareSqlServerForAssessment.ps1" -DestinationPath "$nestedVMArcBoxDir\prepareSqlServerForAssessment.ps1" -CreateFullPath -FileSource Host -Force
    Invoke-Command -VMName $SQLvmName -ScriptBlock { powershell -File $Using:nestedVMArcBoxDir\prepareSqlServerForAssessment.ps1 } -Credential $winCreds

    # Onboard nested Windows and Linux VMs to Azure Arc
        Write-Header "Fetching Nested VMs"

        $Win2k19vmName = "$namingPrefix-Win2K19"
        $win2k19vmvhdPath = "${Env:ArcBoxVMDir}\ArcBox-Win2K19.vhdx"

        $Win2k22vmName = "$namingPrefix-Win2K22"
        $Win2k22vmvhdPath = "${Env:ArcBoxVMDir}\ArcBox-Win2K22.vhdx"

        $Ubuntu01vmName = "$namingPrefix-Ubuntu-01"
        $Ubuntu01vmvhdPath = "${Env:ArcBoxVMDir}\ArcBox-Ubuntu-01.vhdx"

        $Ubuntu02vmName = "$namingPrefix-Ubuntu-02"
        $Ubuntu02vmvhdPath = "${Env:ArcBoxVMDir}\ArcBox-Ubuntu-02.vhdx"

        # Verify if VHD files already downloaded especially when re-running this script
        if (!((Test-Path $win2k19vmvhdPath) -and (Test-Path $Win2k22vmvhdPath) -and (Test-Path $Ubuntu01vmvhdPath) -and (Test-Path $Ubuntu02vmvhdPath))) {
            <# Action when all if and elseif conditions are false #>
            $Env:AZCOPY_BUFFER_GB = 4
            Write-Output "Downloading nested VMs VHDX files. This can take some time, hold tight..."
            azcopy cp $vhdSourceFolder $Env:ArcBoxVMDir --include-pattern "ArcBox-Win2K19.vhdx;ArcBox-Win2K22.vhdx;ArcBox-Ubuntu-01.vhdx;ArcBox-Ubuntu-02.vhdx;" --recursive=true --check-length=false --log-level=ERROR
        }

        # Create the nested VMs if not already created
        Write-Header "Create Hyper-V VMs"
        $serversDscConfigurationFile = "$Env:ArcBoxDscDir\virtual_machines_itpro.dsc.yml"
        (Get-Content -Path $serversDscConfigurationFile) -replace 'namingPrefixStage', $namingPrefix | Set-Content -Path $serversDscConfigurationFile
        winget configure --file C:\ArcBox\DSC\virtual_machines_itpro.dsc.yml --accept-configuration-agreements --disable-interactivity

        Write-Header "Creating VM Credentials"
        # Hard-coded username and password for the nested VMs
        $nestedLinuxUsername = "jumpstart"
        $nestedLinuxPassword = "JS123!!"

        # Create Linux credential object
        $secLinuxPassword = ConvertTo-SecureString $nestedLinuxPassword -AsPlainText -Force
        $linCreds = New-Object System.Management.Automation.PSCredential ($nestedLinuxUsername, $secLinuxPassword)

        # Restarting Windows VM Network Adapters
        Write-Header "Restarting Network Adapters"
        Start-Sleep -Seconds 5
        Invoke-Command -VMName $Win2k19vmName -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCreds
        Invoke-Command -VMName $Win2k22vmName -ScriptBlock { Get-NetAdapter | Restart-NetAdapter } -Credential $winCreds
        Start-Sleep -Seconds 10

        if ($namingPrefix -ne "ArcBox") {

            # Renaming the nested VMs
            Write-Header "Renaming the nested Windows VMs"
            Invoke-Command -VMName $Win2k19vmName -ScriptBlock { Rename-Computer -newName $using:Win2k19vmName -Restart } -Credential $winCreds
            Invoke-Command -VMName $Win2k22vmName -ScriptBlock { Rename-Computer -newName $using:Win2k22vmName -Restart } -Credential $winCreds

            Get-VM *Win* | Wait-VM -For IPAddress

            Write-Host "Waiting for the nested Windows VMs to come back online...waiting for 10 seconds"

            Start-Sleep -Seconds 10

        }

        # Getting the Ubuntu nested VM IP address
        $Ubuntu01VmIp = Get-VM -Name $Ubuntu01vmName | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Select-Object -Index 0
        $Ubuntu02VmIp = Get-VM -Name $Ubuntu02vmName | Select-Object -ExpandProperty NetworkAdapters | Select-Object -ExpandProperty IPAddresses | Select-Object -Index 0

        # Configuring SSH for accessing Linux VMs
        Write-Output "Generating SSH key for accessing nested Linux VMs"

        $null = New-Item -Path ~ -Name .ssh -ItemType Directory
        ssh-keygen -t rsa -N '' -f $Env:USERPROFILE\.ssh\id_rsa

        Copy-Item -Path "$Env:USERPROFILE\.ssh\id_rsa.pub" -Destination "$Env:TEMP\authorized_keys"

        # Automatically accept unseen keys but will refuse connections for changed or invalid hostkeys.
        Add-Content -Path "$Env:USERPROFILE\.ssh\config" -Value "StrictHostKeyChecking=accept-new"

        Get-VM *Ubuntu* | Copy-VMFile -SourcePath "$Env:TEMP\authorized_keys" -DestinationPath "/home/$nestedLinuxUsername/.ssh/" -FileSource Host -Force -CreateFullPath

        if ($namingPrefix -ne "ArcBox") {

                # Renaming the nested linux VMs
                Write-Output "Renaming the nested Linux VMs"

                Invoke-Command -HostName $Ubuntu01VmIp -KeyFilePath "$Env:USERPROFILE\.ssh\id_rsa" -UserName $nestedLinuxUsername -ScriptBlock {

                    Invoke-Expression "sudo hostnamectl set-hostname $using:ubuntu01vmName;sudo systemctl reboot"

                }

                Restart-VM -Name $ubuntu01vmName

                Invoke-Command -HostName $Ubuntu02VmIp -KeyFilePath "$Env:USERPROFILE\.ssh\id_rsa" -UserName $nestedLinuxUsername -ScriptBlock {

                    Invoke-Expression "sudo hostnamectl set-hostname $using:ubuntu02vmName;sudo systemctl reboot"

                }

                Restart-VM -Name $ubuntu02vmName

            }

        Get-VM *Ubuntu* | Wait-VM -For IPAddress

        Write-Host "Waiting for the nested Linux VMs to come back online...waiting for 10 seconds"

        Start-Sleep -Seconds 10

    # Removing the LogonScript Scheduled Task so it won't run on next reboot
    Write-Header "Removing Logon Task"
    if ($null -ne (Get-ScheduledTask -TaskName "ArcServersLogonScript" -ErrorAction SilentlyContinue)) {
        Unregister-ScheduledTask -TaskName "ArcServersLogonScript" -Confirm:$false
    }

Write-Header "Creating deployment logs bundle"

$RandomString = -join ((48..57) + (97..122) | Get-Random -Count 6 | % {[char]$_})
$LogsBundleTempDirectory = "$Env:windir\TEMP\LogsBundle-$RandomString"
$null = New-Item -Path $LogsBundleTempDirectory -ItemType Directory -Force

#required to avoid "file is being used by another process" error when compressing the logs
Copy-Item -Path "$Env:ArcBoxLogsDir\*.log" -Destination $LogsBundleTempDirectory -Force -PassThru
Compress-Archive -Path "$LogsBundleTempDirectory\*.log" -DestinationPath "$Env:ArcBoxLogsDir\LogsBundle-$RandomString.zip" -PassThru

Stop-Transcript