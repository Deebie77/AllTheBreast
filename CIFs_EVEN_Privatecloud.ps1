

Import-module DataOntap
### Dependencies || Host needs DATAONTAP module ( powershell cmdlets ), 
### ---There is enough space on the storage aggregates especially the Secondary Snapmirror and DR Sites, 
### ---There is connectivity to all storage clusters and/or service accounts to login and administer

$even_svmname            = "pcu012fs25"                                  
$even_rootvolume         = "pcu012fs25_root"                             
$even_prootaggr_location	= "pcuntap01c_ssd_aggr2"                        
$even_srootaggr_location = "pcuntap01d_ssd_aggr2"                        
$even_Computername 		= $even_Computername                                 
$even_Pnode 				= "pcuntap01c"                                  
$even_snode 				= "pcuntap01d"                                  
$even_SVM_IP 			= "10.135.12.25"                                
$VLAN_ID 			= "2012"                                        	
$Failovergroup 		= "cifs" + $Vlan_ID                                    	
$Domainname 		= "ShorensteinPC.ysicloud.com"                  	
$Subnet_Mask 		= "255.255.255.0"                               	
$GW 				= "10.135.12.254"                               	
$Broadcast_Domain 	= $Failovergroup 	                                
$DNS1 				= "10.135.12.11"                                	
$DNS2 				= "10.135.12.12"                                	
$MTU 				= "1500"                                        	
$even_volname		= $even_svmname + "_usersdefpaths"               
$DCs				= ($DNS1,$DNS2)                                 	
$ClientACL			= "0.0.0.0/0"                              	


$odd_svmname            	= "pcu012fs26"
$odd_rootvolume         	= "pcu012fs26_root"
$odd_prootaggr_location	= "pcuntap02c_ssd_aggr2"
$odd_srootaggr_location 	= "pcuntap02d_ssd_aggr2"
$odd_Computername 			= $odd_svmname
$odd_Pnode 				= "pcuntap02c"
$odd_snode 				= "pcuntap02d"
$odd_SVM_IP 				= "10.135.12.26"
$odd_volname				= $odd_svmname + "_usersdefpaths"

$evencluster				=	"pcuntap01"
$oddcluster			=	"pcuntap02"
$drcluster				=	"pcuntap08"


######################################################
############################ CREATE even SVM ##########
######################################################


Connect-nccontroller $evencluster

"";">>>>> STEP 1/15: Create SVM Shell"
new-ncvserver -Name $even_svmname -RootVolume $even_rootvolume -RootVolumeAggregate $even_prootaggr_location -RootVolumeSecurityStyle mixed -Language C.UTF-8

"";">>>>> STEP 2/15: Configure SVM Allowed Protocols"
set-ncvserver -name $even_svmname -DisallowedProtocols nfs,fcp,iscsi,ndmp

## Confirm if VLANs already exists

"";">>>>> STEP 3/15: Create SVM VLAN taggings"
new-ncnetportvlan e0e -node $even_Pnode -VlanID $VLAN_ID
new-ncnetportvlan e0g -node $even_Pnode -VlanID $VLAN_ID
new-ncnetportvlan e0e -node $even_snode -VlanID $VLAN_ID
new-ncnetportvlan e0g -node $even_snode -VlanID $VLAN_ID

## Confirm if Broadcast domains already exists

"";">>>>> STEP 4/15: Create SVM Broadcast Domain (Failovergroup)"
New-NcNetPortBroadcastDomain -Name $Broadcast_Domain -ipspace Default -mtu $mtu
set-ncnetportbroadcastdomain -name $Broadcast_Domain -addport $even_Pnode":e0e-"$VLAN_ID
set-ncnetportbroadcastdomain -name $Broadcast_Domain -addport $even_Pnode":e0g-"$VLAN_ID
set-ncnetportbroadcastdomain -name $Broadcast_Domain -addport $even_snode":e0e-"$VLAN_ID
set-ncnetportbroadcastdomain -name $Broadcast_Domain -addport $even_snode":e0g-"$VLAN_ID

## Check if IP is not taken or reserved
"";">>>>> STEP 5/15: Create SVM LIF and Configure"
New-NcNetInterface -Name "$($even_svmname)_cifs_lif1" -Vserver $even_svmname -Role data -Node $even_Pnode -Port e0e-$($VLAN_ID) -DataProtocols cifs -Address $even_SVM_IP -Netmask $Subnet_Mask -FirewallPolicy mgmt -AdministrativeStatus up -Failovergroup $Failovergroup 	 -FailoverPolicy system-defined
	
"";">>>>> STEP 6/15: GATEWAY configuration on LIF"	
New-NcNetRoute -VserverContext $even_svmname -Destination 0.0.0.0/0 -Gateway $GW 

"";">>>>> STEP 7/15: Configure DNS on SVM (setup Preferred DC on SVM)"	
	
New-NcNetDns -VserverContext $even_svmname -domains $Domainname -NameServers $dns1,$dns2
	
"";">>>>> STEP 8/15: Configure preferred domain controller on SVM"		

add-nccifspreferreddomaincontroller -VserverContext $even_svmname -domain $Domainname -domaincontrollers $dns1,$dns2

"";">>>>> STEP 9/15: Online Cifs Vserver and Add 'A' Record on Target Domain "	

Add-NcCifsServer -VserverContext $even_svmname -name $even_computername -Domain $domainname -OrganizationalUnit CN=Computers -AdministrativeStatus up

################ Remote powershell session on target DC's user input required for now unless automated with General service account
############ Remote session seems to be funny .... error 

#The WinRM client cannot process the request. Default 
#authentication may be used with an IP address under the following conditions: the transport is HTTPS or the destination is in the TrustedHosts list, and 
#explicit credentials are provided. Use winrm.cmd to configure TrustedHosts. Note that computers in the TrustedHosts list might not be authenticated. For more 
#information on how to set TrustedHosts run the following command: winrm help config. For more information, see the about_Remote_Troubleshooting Help topic.


switch -Wildcard ($Domainname){
'asp1.yardi.com' {$message = 'Insert Credentials for ASP1'}
"*.ysicloud.com" {$message = 'Insert Credentials for YSICLOUD'}
}

$creds = Get-Credential -Message $message
foreach ($DC in $DCs)
{
	if (Test-Connection $DC -Count 2 -Quiet)
	{
		$session = New-PSSession -ComputerName $DC -Credential $creds
		if ($session)
		{
		##Add-DnsServerResourceRecordA -Name $Computername -ZoneName $Domainname -AllowUpdateAny -IPv4Address $SVM_IP -TimeToLive 01:00:00   			#### Works directly on DC
			Invoke-Command -Session $session {Add-DnsServerResourceRecordA -Name $using:svmname -IPv4Address $using:SVM_IP -ZoneName $using:Domainname} #### Works directly on 'any' ysicloud server
			##Invoke-Command -Session $session {Get-DnsServerResourceRecord -Name tjfs181 -ZoneName $using:Domain}
			$session | Remove-PSSession; break
		}
	}
}
#################

"";">>>>> STEP 10/15: Configure default Export Rule"	

New-NcExportRule -VserverContext $even_svmname -protocol cifs -ReadOnlySecurityFlavor any -ReadWriteSecurityFlavor any -ClientMatch $ClientACL -Index 1 -EnableSetUid -policy default

"";">>>>> STEP 11/15: Creating LS Root_volumes"	

New-NcVol -name "$($even_svmname)_rootvol_m1" -VserverContext $even_svmname -aggregate $even_prootaggr_location -size 10gb -state online -type dp -SecurityStyle mixed -SpaceReserve volume -JunctionPath $null
New-NcVol -name "$($even_svmname)_rootvol_m2" -VserverContext $even_svmname -aggregate $even_srootaggr_location -size 10gb -state online -type dp -SecurityStyle mixed -SpaceReserve volume -JunctionPath $null
set-ncvolsize -vservercontext $even_svmname -name "$($even_svmname)_root" -newsize 10gb

"";">>>>> STEP 12/15: Syncing LS Root_volumes"
New-NcSnapmirror "//$($even_svmname)/$($even_svmname)_rootvol_m1" "//$($even_svmname)/$($even_svmname)_root" -type ls -Schedule 15min
New-NcSnapmirror "//$($even_svmname)/$($even_svmname)_rootvol_m2" "//$($even_svmname)/$($even_svmname)_root" -type ls -Schedule 15min
Invoke-NcSnapmirrorLsInitialize "//$($even_svmname)/$($even_svmname)_root"

"";">>>>> STEP 13/15: Create Volume, Namespace and shares and Snapshot Policy" 

New-NcVol -Name $even_volname -Aggregate $even_prootaggr_location -size 500g -SpaceReserve none -snapshotpolicy fs_snapshots -VserverContext $even_svmname  -JunctionPath "/$($even_volname)" -SecurityStyle ntfs -snapshotreserve 0
Set-NcSnapshotAutodelete -key state -value on -VserverContext $even_svmname -Volume $even_volname
add-NcCifsShare -vservercontext $even_svmname -path "/$($even_svmname)_usersdefpaths" -name usersdefpaths





######################################################
############################ CREATE odd SVM ##########
######################################################

Connect-nccontroller $oddcluster

"";">>>>> STEP 1/15: Create SVM Shell"
new-ncvserver -Name $odd_svmname -RootVolume $odd_rootvolume -RootVolumeAggregate $odd_prootaggr_location -RootVolumeSecurityStyle mixed -Language C.UTF-8

"";">>>>> STEP 2/15: Configure SVM Allowed Protocols"
set-ncvserver -name $odd_svmname -DisallowedProtocols nfs,fcp,iscsi,ndmp

## Confirm if VLANs already exists

"";">>>>> STEP 3/15: Create SVM VLAN taggings"
new-ncnetportvlan e0e -node $odd_Pnode -VlanID $VLAN_ID
new-ncnetportvlan e0g -node $odd_Pnode -VlanID $VLAN_ID
new-ncnetportvlan e0e -node $odd_snode -VlanID $VLAN_ID
new-ncnetportvlan e0g -node $odd_snode -VlanID $VLAN_ID

## Confirm if Broadcast domains already exists

"";">>>>> STEP 4/15: Create SVM Broadcast Domain (Failovergroup)"
New-NcNetPortBroadcastDomain -Name $Broadcast_Domain -ipspace Default -mtu $mtu
set-ncnetportbroadcastdomain -name $Broadcast_Domain -addport $odd_Pnode":e0e-"$VLAN_ID
set-ncnetportbroadcastdomain -name $Broadcast_Domain -addport $odd_Pnode":e0g-"$VLAN_ID
set-ncnetportbroadcastdomain -name $Broadcast_Domain -addport $odd_snode":e0e-"$VLAN_ID
set-ncnetportbroadcastdomain -name $Broadcast_Domain -addport $odd_snode":e0g-"$VLAN_ID

## Check if IP is not taken or reserved
"";">>>>> STEP 5/15: Create SVM LIF and Configure"
New-NcNetInterface -Name "$($odd_svmname)_cifs_lif1" -Vserver $odd_svmname -Role data -Node $odd_Pnode -Port e0e-$($VLAN_ID) -DataProtocols cifs -Address $odd_SVM_IP -Netmask $Subnet_Mask -FirewallPolicy mgmt -AdministrativeStatus up -Failovergroup $Failovergroup 	 -FailoverPolicy system-defined
	
"";">>>>> STEP 6/15: GATEWAY configuration on LIF"	
New-NcNetRoute -VserverContext $odd_svmname -Destination 0.0.0.0/0 -Gateway $GW 

"";">>>>> STEP 7/15: Configure DNS on SVM (setup Preferred DC on SVM)"	
	
New-NcNetDns -VserverContext $odd_svmname -domains $Domainname -NameServers $dns2,$dns1
	
"";">>>>> STEP 8/15: Configure preferred domain controller on SVM"		

add-nccifspreferreddomaincontroller -VserverContext $odd_svmname -domain $Domainname -domaincontrollers $dns2,$dns1

"";">>>>> STEP 9/15: Online Cifs Vserver and Add 'A' Record on Target Domain "	

Add-NcCifsServer -VserverContext $odd_svmname -name $odd_computername -Domain $domainname -OrganizationalUnit CN=Computers -AdministrativeStatus up

################ Remote powershell session on target DC's user input required for now unless automated with General service account
############ Remote session seems to be funny .... error 

#The WinRM client cannot process the request. Default 
#authentication may be used with an IP address under the following conditions: the transport is HTTPS or the destination is in the TrustedHosts list, and 
#explicit credentials are provided. Use winrm.cmd to configure TrustedHosts. Note that computers in the TrustedHosts list might not be authenticated. For more 
#information on how to set TrustedHosts run the following command: winrm help config. For more information, see the about_Remote_Troubleshooting Help topic.


switch -Wildcard ($Domainname){
'asp1.yardi.com' {$message = 'Insert Credentials for ASP1'}
"*.ysicloud.com" {$message = 'Insert Credentials for YSICLOUD'}
}

$creds = Get-Credential -Message $message
foreach ($DC in $DCs)
{
	if (Test-Connection $DC -Count 2 -Quiet)
	{
		$session = New-PSSession -ComputerName $DC -Credential $creds
		if ($session)
		{
		##Add-DnsServerResourceRecordA -Name $Computername -ZoneName $Domainname -AllowUpdateAny -IPv4Address $SVM_IP -TimeToLive 01:00:00   			#### Works directly on DC
			Invoke-Command -Session $session {Add-DnsServerResourceRecordA -Name pca201fs25 -IPv4Address 10.97.201.25 -ZoneName InvestorCafePC.yardi.cloud} #### Works directly on 'any' ysicloud server
			##Get-DnsServerResourceRecord -Name tjfs181 -ZoneName InvestorCafePC.yardi.cloud
			##Add-DnsServerResourceRecordA -Name pca201fs25 -IPv4Address 10.97.201.25 -ZoneName InvestorCafePC.yardi.cloud
			$session | Remove-PSSession; break
		}
	}
}
#################

"";">>>>> STEP 10/15: Configure default Export Rule"	

New-NcExportRule -VserverContext $odd_svmname -protocol cifs -ReadOnlySecurityFlavor any -ReadWriteSecurityFlavor any -ClientMatch $ClientACL -Index 1 -EnableSetUid -policy default

"";">>>>> STEP 11/15: Creating LS Root_volumes"	

New-NcVol -name "$($odd_svmname)_rootvol_m1" -VserverContext $odd_svmname -aggregate $odd_prootaggr_location -size 10gb -state online -type dp -SecurityStyle mixed -SpaceReserve volume -JunctionPath $null
New-NcVol -name "$($odd_svmname)_rootvol_m2" -VserverContext $odd_svmname -aggregate $odd_srootaggr_location -size 10gb -state online -type dp -SecurityStyle mixed -SpaceReserve volume -JunctionPath $null
set-ncvolsize -vservercontext $odd_svmname -name "$($odd_svmname)_root" -newsize 10gb

"";">>>>> STEP 12/15: Syncing LS Root_volumes"
New-NcSnapmirror "//$($odd_svmname)/$($odd_svmname)_rootvol_m1" "//$($odd_svmname)/$($odd_svmname)_root" -type ls -Schedule 15min
New-NcSnapmirror "//$($odd_svmname)/$($odd_svmname)_rootvol_m2" "//$($odd_svmname)/$($odd_svmname)_root" -type ls -Schedule 15min
Invoke-NcSnapmirrorLsInitialize "//$($odd_svmname)/$($odd_svmname)_root"

"";">>>>> STEP 13/15: Create Volume, Namespace and shares and Snapshot Policy" 

New-NcVol -name "sm_$($even_volname)" -VserverContext $odd_svmname -aggregate $odd_prootaggr_location -size 500gb -state online -type dp -SecurityStyle mixed -SpaceReserve none -JunctionPath $null
#New-NcVol -Name $odd_volname -Aggregate $odd_prootaggr_location -size 500g -SpaceReserve none -snapshotpolicy fs_snapshots -VserverContext $odd_svmname  -JunctionPath "/$($volname)" -SecurityStyle ntfs -snapshotreserve 0
#Set-NcSnapshotAutodelete -key state -value on -VserverContext $odd_svmname -Volume $odd_volname


######################################################
############################ CREATE SNAPMIRROR ##########
######################################################


"";">>>>> STEP 16/15: Create Snapmirror Relationships"

#### Source Cluster to Backup cluster  -----  Snapmirror
#### Source Cluster to DR Cluster    ------ Snapvault

######ASSUME Clusters are Peered already
## New Variables scratch
$sourceVserver 			= $even_svmname
$destinationVserver 	= $odd_svmname
$sourceCluster 			= $evencluster
$destinationCluster 	= $oddcluster
$sourcevolume 			= $even_volname
$destinationvolume 		= "sm_" + $sourcevolume
$DefaultSize      		= '500g'
$destinationaggregate 	= $even_prootaggr_location
##
## connect to source cluster to initiate the vserver peer request
Connect-NcController $sourceCluster

New-NcVserverPeer -Vserver $sourceVserver -peerCluster $destinationcluster -peervserver $destinationVserver -localname $destinationVserver -Application snapmirror

## connect to Destination cluster to accept the vserver peer request
Connect-NcController $destinationCluster

confirm-ncvserverpeer -PeerVserver $sourceVserver -Vserver $destinationVserver
#New-NcVol -name "sm_$($even_svmname)_usersdefpaths" -VserverContext $destinationVserver -aggregate $destinationaggregate -size $DefaultSize -state online -type dp -SecurityStyle UNIX -SpaceReserve none -JunctionPath $null

## Creating Snapmirror relationship Source >> Destination
New-NcSnapmirror -SourceCluster $sourceCluster -DestinationCluster $destinationCluster -SourceVserver $sourceVserver -SourceVolume $sourcevolume -DestinationVserver $destinationVserver -DestinationVolume $destinationvolume -schedule fs_snapmirror -type dp -policy MirrorAllSnapshots
Invoke-NcSnapmirrorInitialize -DestinationVserver $destinationVserver -DestinationVolume $destinationvolume


"";">>>>> STEP 16/15: Create Stellar objects"


##Add-DnsServerResourceRecordA -Name pcv087fs25 -ZoneName OConnorPC.yardi.cloud -AllowUpdateAny -IPv4Address 10.185.87.25 -TimeToLive 01:00:00



net port mod -node pcvntap02c -port e0e -mtu 1500 -autonegotiate-admin true -duplex-admin auto -speed-admin auto -flowcontrol-admin none -up-admin true -ipspace Default -ignore-health-status false

net port mod -node pcvntap01c -port e0e -mtu 1500 -autonegotiate-admin true -duplex-admin auto -speed-admin auto -flowcontrol-admin none -up-admin true -ipspace Default -ignore-health-status false -autorevert-delay



Yardi123@welcome@123
