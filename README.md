# MultivalidatorPSScript
## Overview
This is a semi-simple Powershell script to generate a multiaddress validator runtime in Docker providing attestations for 'n' addresses

This script currently supports creating a single validator instance in Docker validating for multiple addresses whose keypairs are stored and referenced in the same bind mounted data-dir on the host (c:\prysm\\$validatorname\\[keyfiles] by default). 

## ----WARNING----
This script is highly experimental and a work-in-progress without full considerations for security. It unlocks your account in Geth while utilizing RPC on the localhost which places you at risk. Additionally, passwords entered, while stored as securestrings, may be accessible in memory while the Powershell instance open. ***USE AT YOUR OWN RISK***. The author may not be held liable for its use or misue. This script has ONLY been tested using Prysm-Validator and the Goerli testnet. While it is technically network independent (transactions and deposit data will be sent from whatever network your Geth node is connected to with a valid account), it should be carefully reviewed before using it for anything else.

## Prerequisites and Assumptions
1. The latest version of Docker Desktop installed and running.
2. The latest version of Geth installed and synced (fast sync is fine).
3. Powershell v4, and local administrator rights (or the ability to escalate privileges via run-as for powershell).
4. An account imported to Geth with enough ETH to fund the number of validators you need (n * 32ETH) plus some to spare for gas!
5. Local Prysm beacon node (or other Beacon Node validators can connect to) running and listening to serve the validators created (see https://prylabs.net/)
6. Tje script extracts the deposit-data from the 'account create' function of Prysm which includes a lot of junk text. It uses a static string lenght of 842 to do so. If Prysmatic Labs should change the deposit data length, the script will break.

## Details
See code comments for additional details.
