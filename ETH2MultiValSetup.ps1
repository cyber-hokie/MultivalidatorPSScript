<# *********Warning**********
   this script is highly experimental, and highly insecure as it unlocks your account in Geth while utilizing RPC on the localhost. 
   Additionally, passwords entered, while stored as securestrings, may be accessible in memory while the Powershell instance open. USE AT YOUR OWN RISK.
   The author may not be held liable for its use
   *********Warning**********

   Description: 
   
   This script will automatically generate validator keys and deposit data for any number of Prysm validators specified, as well as automatically start a 
   Prysm multivalidator docker containers. It can be modified easily for single validator in a single runtime support by adjusting the commented out portions of the script below.
   I originally set up 1 runtime/container per address/account to participate in the graffiti wall on beaconcha.in faster. but the resource utilization is rough. 
   The script has ONLY been tested on Goerli and has NOT been tested for Mainnet (since the beacon chain deposit contract has yet to be deployed to mainnet as
   of writing this).

   Dependencies:

   - The latest version of Docker Desktop installed and running.
   - The latest version of Geth installed and synced (fast sync is fine).
   - Powershell v4, and local administrator rights (or the ability to escalate privileges via run-as for powershell).
   - An account imported to Geth with enough ETH to fund the number of validators you need (n * 32ETH) plus some to spare for gas!
   - Local prysm beacon node running and listening to serve the validators created (see https://prylabs.net/)
   - Also, the script extracts the deposit-data from the 'account create' function of Prysm which includes a lot of junk text. It uses a static string lenght of 842 to do so.
     If Prysmatic Labs should change the deposit data length, the script will break.

    h/t to Stefan in the Prysmatic Labs Discord for his initial lightweight Bash version of this    
#>


$range = @()
$range2 = @()

## << Get the latest Prysm Validator Docker release >>
echo "-------------------------------------------------"
echo "Pulling latest Prysm Validator Release Image"
echo "-------------------------------------------------"
echo ""
docker pull gcr.io/prysmaticlabs/prysm/validator:latest
echo ""

## << Unlock the Geth Acconunt using the user input account public key, user supplied password, and duration to keep the account unlocked for which should >>
## << be enough time for the script to complete. The script should be able to generate 50 addresses in less than 5 minutes on a reasonable computer >>
echo "-------------------------------------------------"
echo "Unlock Geth Account for Transactions"
echo "-------------------------------------------------"
[string]$gethaddress = Read-Host -Prompt "Please Enter Account Address (0x....)"
Do {
    $gethpass=Read-Host -Prompt "Enter Geth Account Password for Account Sending Funds" -AsSecureString
    $BSTRgethpass = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($gethpass)
    $gethpassplain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRgethpass)
    $gethpassconf=Read-Host -Prompt "Please Re-enter To Verify Correctness" -AsSecureString
    $BSTRgethpassconf = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($gethpassconf)
    $gethpassconfplain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTRgethpassconf)

    If ($gethpassplain -ceq $gethpassconfplain) {
       $gethpassword = $gethpassplain
       } else {
       Write-Host "Passwords do not match. Please try again."
       $gethpassword = ""
       }
    }
    Until ($gethpassplain -ceq $gethpassconfplain)
[int]$durationsecs = Read-Host -Prompt "Please enter the duration to keep the account unlocked (in seconds)"
[int]$durationconv = $durationsecs * 1000
geth attach ipc:\\.\pipe\geth.ipc --exec "web3.personal.unlockAccount('${gethaddress}','${gethpassword}', ${durationconv})"
echo ""
echo "-------------------------------------------------"

## << Requests user input for validator information including the name of the validator (will be used for data-dir created on local host, and the Docker container name) and password >>
## << to secure the keys (password will apply to all validators created. Currently there's no way to specify an individual password for each unless setting them up 1 by 1. If this >>
## << is for a multivalidator in one runtime, it will only ask for name, password, and number of validator addresses you wish to generate keypairs and deposit data for so. However, >>
## << if you are setting this up to do 1 validator runtime per 1 address, then it will also ask for a range (e.g. I enter 90 for validator count, and 11 as the range start point if >>
## << I already have 10 other validators running I used the script to create before so I don't merge them. It will create prysm-validator11 to prysm-validator100, with 90 specified >>

echo "Provide validator setup information"
echo "-------------------------------------------------"
echo ""
[string]$validatorname = Read-Host -Prompt "What would you like to name the validator and Docker container?"
[int]$validatorcount = Read-Host -Prompt "Please enter the number of validators you wish to create"
[int]$validatorcount = [math]::Round($validatorcount, [System.MidpointRounding]::AwayFromZero)

## << If you want to set up 1 validator per 1 keypair/address uncomment $rangestart, $rangeend and $range below, and comment out the other $range and $rangeend. See more below >>

<#
[int]$rangestart = Read-Host -Prompt "Please enter the number of the first validator you want the range to start on (usually this is 1 unless you've previously created validators and don't want the script to overwrite other validators)"
[int]$rangestart = [math]::Round($rangestart, [System.MidpointRounding]::AwayFromZero)
[int]$rangend = $rangestart + ($validatorcount -1)
#>

[int]$rangeend = $validatorcount
$range = 1..$rangeend
#range = $rangestart..$rangeend
echo "Next, please enter a password for the validator account keys"
Do {
    $valpass=Read-Host -Prompt "Enter Password for Validator Accounts" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($valpass)
    $valpassplain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    $passconf=Read-Host -Prompt "Confirm Password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($passconf)
    $passconfplain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)

    If ($valpassplain -ceq $passconfplain) {
       $valpassword = $valpassplain
       } else {
       Write-Host "Passwords do not match. Please try again."
       $valpassword = ""
       }
    }
    Until ($valpassplain -ceq $passconfplain)

## << Helper variables to clean up formatting for the javascript function so it is acceptable by keystoremanager due to powershell single quote limitations >>

$ksm = "{'path':'/data','passphrase':'${valpassword}'}"
$ksm2 = $ksm.ToString() -replace '''','\"'
$ksm3 = $ksm2.ToString()

## << For loop to iterate through the numbers in the range defined above to generate the deposit data and transaction data for submission to the Geth node. >>
## << For multivalidator setup, it's 1..$rangeend ($validatorcount - 1), for individual validator setup, it's $rangestart..$rangeend ($rangestart + ($validatorcount - 1)). >>
## << This will also start the validator(s) Docker container(s) with the appropriate configuration. This may be updated later to include things like --graffiti using 'docker update'>>
 
foreach($number in $range){
    echo ""
    echo ""
    echo "-------------------------------------------------"
    echo "Generating Validator #${number} Keys and Deposit-Data"
    echo "-------------------------------------------------"
    echo ""    
    echo "-------------"
    echo "Deposit-Data"
    echo "-------------"
    $beaconcontract = "0x5ca1e00004366ac85f492887aaab12d0e6418876"
        
    ## << If you want to set up 1 validator per address/keypair uncomment the below line and comment out the above. Also see $rangestart and $range definitions above >>

    $depositdata = docker run -it --rm -v c:/prysm/${validatorname}:/data gcr.io/prysmaticlabs/prysm/validator:latest accounts create --keystore-path=/data --password=$valpassword | select-string "\b\w{842}"
    #$depositdata = docker run -it --rm -v c:/prysm/validator${number}:/data gcr.io/prysmaticlabs/prysm/validator:latest accounts create --keystore-path=/data --password=$valpassword | select-string "\b\w{842}"
    $depositdata
    $send_cmd = "web3.eth.sendTransaction({from:web3.eth.coinbase, to:'${beaconcontract}', value:web3.toWei(32,'ether'), data:'${depositdata}'})"
    $send_cmdclean = $send_cmd.Replace("`n","").Replace("`r","")
       
       echo ""
       echo ""
       echo "-------------------------------------------------"
       echo "Transaction Data for Validator #${number}"
       echo "-------------------------------------------------"
       
       $send_cmdclean
 
       echo ""
       echo ""
       echo "-------------------------------------------------"
       echo "Sending Transaction for Validator #${number}"
       echo "-------------------------------------------------"
       
       $gethcommand = "geth attach ipc:\\.\pipe\geth.ipc --exec `"${send_cmdclean}`""
       Invoke-Expression $gethcommand
       
       echo ""
       echo ""
       
       ## << If creating 1 runtime per keypair/address remove the comments from the commands below and comment out the "Spawning Multivalidator Docker Container" section >>
       
       <#
       echo "-------------------------------------------------"
       echo "Spawning Validator #${number} Docker Container"
       echo "-------------------------------------------------"
       docker stop prysm-multivalidator2
       docker rm prysm-multivalidator2
       docker run -it -d -v c:/prysm/validator${number}:/data --network="host" --name prysm-validator${number} --restart always gcr.io/prysmaticlabs/prysm/validator:latest --beacon-rpc-provider=127.0.0.1:4000 --keymanager=keystore --keymanageropts=${ksm3}
       Start-Sleep -s 1
       #>

    }
    echo "-------------------------------------------------"
    echo "Spawning MultiValidator Docker Container"
    echo "-------------------------------------------------"
    docker stop prysm-${validatorname}
    docker rm prysm-${validatorname}
    docker run -it -d -v c:\prysm\${validatorname}:/data --network="host" --name "prysm-${validatorname}" --restart always gcr.io/prysmaticlabs/prysm/validator:latest --beacon-rpc-provider=127.0.0.1:4000 --keymanager=keystore --keymanageropts=${ksm3}
    Start-Sleep -s 1

## << Finally, the script searches the validator data directory on the host (.\$validatorname) in a recursive manner, to find all validatorprivatekey files within, and extracts >>
## << and returns the public key for each, so that you may track deposit status, or hopefully import/enter into dashboard tools such as those at beaconcha.in >>

echo ""
echo "-------------------------------------------------"
echo "Gathering Validator Public Keys"
echo "-------------------------------------------------"
echo ""
select-string -path C:\prysm\${validatorname}\validatorpriv* -pattern '(?<={"publickey":")(.*?)(?=")' -allmatches  |
  foreach-object {$_.matches} |
   foreach-object {"0x"+$_.groups[1].value} |
    Select-Object -Unique