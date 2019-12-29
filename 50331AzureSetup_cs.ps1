### Azure setup script for 50331D course Virtual Machines.  This script creates A DC running Windows Server 2016 (NYC-DC1) and a Windows 10 client (Student10)
### Configure Objects & Variables
Set-StrictMode -Version 2.0
$SubscriptionName = (Get-AzureRMSubscription)[0].Name                  # This variable should be assigned your "Subscription Name"
$CloudDriveMP = (Get-CloudDrive).MountPoint
# New-PSDrive -Name "F" -PSProvider "FileSystem" -Root $CloudDriveMP
# $WorkFolder = "f:\labfiles.50331d\"
$WorkFolder = "/home/$env:USER/clouddrive/labfiles.50331d/"
Set-Location $WorkFolder
$AzureSetupFiles = $WorkFolder + "50331azuresetup.zip"
Expand-Archive $AzureSetupFiles $WorkFolder -Force -ErrorAction "SilentlyContinue"
$Location = "EASTUS"
$NamePrefix = ("cs" + (Get-Date -Format "HHmmss")).ToLower()           # Replace "cs" with your initials
$ResourceGroupName = $NamePrefix + "rg"
$StorageAccountName = $NamePrefix.tolower() + "sa"                     # Must be lower case
$SAShare = "50331d"
$VMDC = "nyc-dc1"
$VMCLX = "student10"
$PublicIPDCName = "PublicIPDC"
$PublicIPCLXName = "PublicIPCLX"
$PW = Write-Output 'Pa$$w0rdPa$$w0rd' | ConvertTo-SecureString -AsPlainText -Force     # Password for Administrator account
$AdminCred = New-Object System.Management.Automation.PSCredential("adminz",$PW)
$CSETMP = $WorkFolder + "50331customscriptextension.tmp"
$CSENew = $WorkFolder + "50331cse.new"

### Log start time of script
$logFilePrefix = "50331AzureSetup" + (Get-Date -Format "HHmm") ; $logFileSuffix = ".txt" ; $StartTime = Get-Date 
"Create Azure VMs (50331)"   >  $WorkFolder$logFilePrefix$logFileSuffix
"Start Time: " + $StartTime >> $WorkFolder$logFilePrefix$logFileSuffix

### Login to Azure
# Connect-AzureRmAccount
$Subscription = Get-AzureRmSubscription -SubscriptionName $SubscriptionName | Select-AzureRmSubscription

### Create Resource Group, Storage Account & Setup Resources
$ResourceGroup = New-AzureRmResourceGroup -Name $ResourceGroupName  -Location $Location
$StorageAccount = New-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $StorageAccountName -Location $location -Type Standard_RAGRS
$StorageAccountKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $ResourceGroupName -Name $StorageAccountName)[0].Value
$StorageAccountContext = New-AzureStorageContext -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
$BlobShare = New-AzureStorageContainer -Name $SAShare.ToLower() -Context $StorageAccountContext -Permission Container -Verbose
$FileShare = New-AzureStorageShare $SAShare.ToLower() -Context $StorageAccountContext
# Create Custom Script Extension File (CSE)
Write-Output '### Copy From File Share Using Mapped Network Drive' > $CSENew
Write-Output "`$WorkFolder = 'c:\labfiles.50331d\' ; `$SAShare = '$SAShare'" >> $CSENew
Write-Output 'New-Item -Path $WorkFolder -Type Directory -Force' >> $CSENew
Write-Output "`$StorageAccountName = '$StorageAccountName'" >> $CSENew
Write-Output "`$StorageAccountKey = '$StorageAccountKey'" >> $CSENew
Get-Content $CSENew, $CSETMP > 50331customscriptextension.ps1
Get-ChildItem $WorkFolder"50331customscriptextension.ps1" | Set-AzureStorageBlobContent -Container $SAShare -Context $StorageAccountContext -Force
Get-ChildItem $WorkFolder"50331azuresetup.zip" | Set-AzureStorageBlobContent -Container $SAShare -Context $StorageAccountContext -Force
Get-ChildItem $WorkFolder"50331customscriptextension.ps1" | Set-AzureStorageFileContent -Share $FileShare -Force
Get-ChildItem $WorkFolder"50331azuresetup.zip" | Set-AzureStorageFileContent -Share $FileShare -Force

### Create Network
$NSGRule1 = New-AzureRmNetworkSecurityRuleConfig -Name "RDPRule" -Protocol Tcp -Direction Inbound -Priority 1001 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 3389 -Access Allow
$NSGRule2 = New-AzureRmNetworkSecurityRuleConfig -Name "MSSQLRule"  -Protocol Tcp -Direction Inbound -Priority 1002 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 1433 -Access Allow
$NSGRule3 = New-AzureRmNetworkSecurityRuleConfig -Name "WinHTTP" -Protocol Tcp -Direction Inbound -Priority 1003 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5985 -Access Allow
$NSGRule4 = New-AzureRmNetworkSecurityRuleConfig -Name "WinHTTPS"  -Protocol Tcp -Direction Inbound -Priority 1004 -SourceAddressPrefix * -SourcePortRange * -DestinationAddressPrefix * -DestinationPortRange 5986 -Access Allow
$NSG1 = New-AzureRMNetworkSecurityGroup -ResourceGroupName $ResourceGroupName -Location $Location -Name "NSG1" -SecurityRules $NSGRule1,$NSGRule2,$NSGRule3,$NSGRule4 -Force
$Subnet10 = New-AzureRmVirtualNetworkSubnetConfig -Name "Subnet10" -AddressPrefix 192.168.10.0/24
$Subnet20 = New-AzureRmVirtualNetworkSubnetConfig -Name "Subnet20" -AddressPrefix 192.168.20.0/24 
$VirtualNetwork1 = New-AzureRmVirtualNetwork -Name "VirtualNetwork1" -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix 192.168.0.0/16 -Subnet $Subnet10, $Subnet20 -Force
$PublicIPDC = New-AzureRmPublicIPAddress -Name $PublicIPDCName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static  
$PublicIPCLX = New-AzureRmPublicIPAddress -Name $PublicIPCLXName -ResourceGroupName $ResourceGroupName -Location $Location -AllocationMethod Static 
$DCNIC1 = New-AzureRmNetworkInterface -Name "DCNIC1" -ResourceGroupName $ResourceGroupName -Location $Location -PrivateIPAddress 192.168.10.100 -SubnetId $VirtualNetwork1.Subnets[0].Id -PublicIPAddressId $PublicIPDC.Id -NetworkSecurityGroupId $NSG1.Id
$DCNIC2 = New-AzureRmNetworkInterface -Name "DCNIC2" -ResourceGroupName $ResourceGroupName -Location $Location -PrivateIPAddress 192.168.20.100 -SubnetId $VirtualNetwork1.Subnets[1].Id -NetworkSecurityGroupId $NSG1.Id
$CLXNIC1 = New-AzureRmNetworkInterface -Name "CLXNIC1" -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $VirtualNetwork1.Subnets[0].Id -PublicIPAddressId $PublicIPCLX.Id -NetworkSecurityGroupId $NSG1.Id
$CLXNIC2 = New-AzureRmNetworkInterface -Name "CLXNIC2" -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $VirtualNetwork1.Subnets[1].Id -NetworkSecurityGroupId $NSG1.Id

### Create VMs
# Domain Controller
$PublisherName = "MicrosoftWindowsServer"
$OfferDC = (Get-AzureRMVMImageOffer -Location $Location -PublisherName $PublisherName | Where-Object {$_.Offer -match "WindowsServer"})[0].Offer 
$SkuDC = (Get-AzureRmVMImagesku -Location $Location -PublisherName $PublisherName -Offer $OfferDC | Where-Object {$_.Skus -match "2016-Datacenter"})[0].Skus
$VMSize = (Get-AzureRMVMSize -Location $Location | Where-Object {$_.Name -match "Standard_DS2"})[0].Name
$VM1 = New-AzureRmVMConfig -VMName $VMDC -VMSize $VMSize
$VM1 = Set-AzureRmVMOperatingSystem -VM $VM1 -Windows -ComputerName $VMDC -Credential $AdminCred -WinRMHttp -ProvisionVMAgent -EnableAutoUpdate
$VM1 = Set-AzureRmVMSourceImage -VM $VM1 -PublisherName $PublisherName -Offer $OfferDC -Skus $SkuDC -Version "latest"
$VM1 = Add-AzureRMVMNetworkInterface -VM $VM1 -ID $DCNIC1.Id -Primary
$VM1 = Add-AzureRMVMNetworkInterface -VM $VM1 -ID $DCNIC2.Id 
$VHDURI1 = (Get-AzureRMStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).PrimaryEndPoints.Blob.ToString() + "vhddc/VHDDC1.vhd"
$VM1 = Set-AzureRmVMOSDisk -VM $VM1 -Name "VHDDC1" -VHDURI $VHDURI1 -CreateOption FromImage
New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VM1 -Verbose
Start-AzureRMVM -Name $VMDC -ResourceGroupName $ResourceGroupName
Set-AzureRmVMCustomScriptExtension -Name "Microsoft.Compute" -TypeHandlerVersion "1.9" -FileName "50331customscriptextension.ps1" -Run "50331customscriptextension.ps1" -ForceRerun $(New-Guid).Guid -ContainerName $SAShare -ResourceGroupName $ResourceGroupName -VMName $VMDC -Location $Location -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
$PublicIPAddress1 = Get-AzureRmPublicIpAddress -Name $PublicIPDCName -ResourceGroupName $ResourceGroupName
Write-Output "The virtual machine has been created.  Wait fifteen (15) minutes and then you may login as Adminz by using Remote Desktop Connection to connect to its Public IP address."
Write-Output  "Public IP Address for $VMDC is: " $PublicIPAddress1.IpAddress

# Windows 10 Client
$PublisherName = "MicrosoftVisualStudio"
$OfferCLX = (Get-AzureRMVMImageOffer -Location $Location -PublisherName $PublisherName | Where-Object {$_.Offer -match "windows"})[0].Offer 
$SkuCLX = (Get-AzureRmVMImagesku -Location $Location -PublisherName $PublisherName -Offer $OfferCLX | Where-Object {$_.Skus -match "windows-10"})[0].Skus
$VMSize = (Get-AzureRMVMSize -Location $Location | Where-Object {$_.Name -match "Standard_DS3"})[0].Name
$VM2 = New-AzureRmVMConfig -VMName $VMCLX -VMSize $VMSize
$VM2 = Set-AzureRmVMOperatingSystem -VM $VM2 -Windows -ComputerName $VMCLX -Credential $AdminCred -WinRMHttp -ProvisionVMAgent -EnableAutoUpdate
$VM2 = Set-AzureRmVMSourceImage -VM $VM2 -PublisherName $PublisherName -Offer $OfferCLX -Skus $SkuCLX -Version "latest"
$VM2 = Add-AzureRMVMNetworkInterface -VM $VM2 -ID $CLXNIC1.Id -Primary
$VM2 = Add-AzureRMVMNetworkInterface -VM $VM2 -ID $CLXNIC2.Id
$VHDURI2 = (Get-AzureRMStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName).PrimaryEndPoints.Blob.ToString() + "vhdclx/VHDCLX1.vhd"
$VM2 = Set-AzureRmVMOSDisk -VM $VM2 -Name "VHDCLX1" -VHDURI $VHDURI2 -CreateOption FromImage
New-AzureRmVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $VM2 -Verbose
Start-AzureRMVM -Name $VMCLX -ResourceGroupName $ResourceGroupName
Set-AzureRmVMCustomScriptExtension -Name "Microsoft.Compute" -TypeHandlerVersion "1.9" -FileName "50331customscriptextension.ps1" -Run "50331customscriptextension.ps1" -ForceRerun $(New-Guid).Guid -ContainerName $SAShare -ResourceGroupName $ResourceGroupName -VMName $VMCLX -Location $Location -StorageAccountName $StorageAccountName -StorageAccountKey $StorageAccountKey
$PublicIPAddress2 = Get-AzureRmPublicIpAddress -Name $PublicIPCLXName -ResourceGroupName $ResourceGroupName
Write-Output "The virtual machine has been created.  Wait ten (10) minutes and then you may login as Adminz by using Remote Desktop Connection to connect to its Public IP address."
Write-Output  "Public IP Address for $VMCLX is: " $PublicIPAddress2.IPAddress

### Delete Resources and log end time of script
"NYC-DC1   Internet IP:  " + $PublicIPAddress1.IpAddress >> $WorkFolder$logFilePrefix$logFileSuffix
"Student10 Internet IP:  " + $PublicIPAddress2.IpAddress >> $WorkFolder$logFilePrefix$logFileSuffix
"Resource Group Name  :  " + $ResourceGroupName + "   # Delete the Resource Group to remove all Azure resources created by this script (e.g. Remove-AzureRMResourceGroup -Name $ResourceGroupName -Force)"  >> $WorkFolder$logFilePrefix$logFileSuffix
$EndTime = Get-Date ; $et = "50331AzureSetup" + $EndTime.ToString("yyyyMMddHHmm")
"End Time:   " + $EndTime >> $WorkFolder$logFilePrefix$logFileSuffix
"Duration:   " + ($EndTime - $StartTime).TotalMinutes + " (Minutes)" >> $WorkFolder$logFilePrefix$logFileSuffix 
Rename-Item -Path $WorkFolder$logFilePrefix$logFileSuffix -NewName $et$logFileSuffix
Get-Content $et$logFileSuffix
### Remove-AzureRMResourceGroup -Name $ResourceGroupName -Verbose -Force

