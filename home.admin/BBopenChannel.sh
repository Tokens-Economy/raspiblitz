#!/bin/bash
_temp="./download/dialog.$$"
_error="./.error.out"

# load network and chain info
network=`cat .network`
chain=$(sudo -bitcoin ${network}-cli -datadir=/home/bitcoin/.${network} getblockchaininfo | jq -r '.chain')

echo ""
echo "*** Precheck ***"

# check if chain is in sync
chainInSync=$(lncli --chain=${network} getinfo | grep '"synced_to_chain": true' -c)
if [ ${chainInSync} -eq 0 ]; then
  echo "FAIL - 'lncli getinfo' shows 'synced_to_chain': false"
  echo "Wait until chain is sync with LND and try again."
  echo ""
  exit 1
fi

# check available funding
confirmedBalance=$(lncli --chain=${network} walletbalance | grep '"confirmed_balance"' | cut -d '"' -f4)
if [ ${confirmedBalance} -eq 0 ]; then
  echo "FAIL - You have 0 SATOSHI in your confirmed LND On-Chain Wallet."
  echo "Please fund your on-chain wallet first and wait until confirmed."
  echo ""
  exit 1
fi

# check number of connected peers
numConnectedPeers=$(lncli --chain=${network} listpeers | grep pub_key -c)
if [ ${numConnectedPeers} -eq 0 ]; then
  echo "FAIL - no peers connected on lightning network"
  echo "You can only open channels to peer nodes to connected to first."
  echo "Use CONNECT peer option in main menu first."
  echo ""
  exit 1
fi

# let user pick a peer to open a channels with
OPTIONS=()
while IFS= read -r grepLine
do
  pubKey=$(echo ${grepLine} | cut -d '"' -f4)
  #echo "grepLine(${pubKey})"
  OPTIONS+=(${pubKey} "")
done < <(lncli --chain=${network} listpeers | grep pub_key)
TITLE="Open (Payment) Channel"
MENU="\nChoose a peer you connected to, to open the channel with: \n "
pubKey=$(dialog --clear \
                --title "$TITLE" \
                --menu "$MENU" \
                14 73 5 \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

clear
if [ ${#pubKey} -eq 0 ]; then
 echo "Selected CANCEL"
 echo ""
 exit 1
fi

# find out what is the minimum amount 
# TODO find a better way - also consider dust and channel reserve
# details see here: https://github.com/btcontract/lnwallet/issues/52
minSat=20000
if [ "${network}" = "bitcoin" ]; then
  minSat=250000
fi
_error="./.error.out"
lncli --chain=${network} openchannel ${CHOICE} 1 0 2>$_error
error=`cat ${_error}`
if [ $(echo "${error}" | grep "channel is too small" -c) -eq 1 ]; then
  minSat=$(echo "${error}" | tr -dc '0-9')
fi

# let user enter a amount
l1="Amount in SATOSHI to fund this channel:"
l2="min required  : ${minSat}"
l3="max available : ${confirmedBalance}"
dialog --title "Funding of Channel" \
--inputbox "$l1\n$l2\n$l3" 10 60 2>$_temp
amount=$(cat $_temp | xargs | tr -dc '0-9')
shred $_temp
if [ ${#amount} -eq 0 ]; then
  echo "FAIL - not a valid input (${amount})"
  exit 1
fi

# build command
command="lncli --chain=${network} openchannel ${pubKey} ${amount} 0"

# info output
clear
echo "******************************"
echo "Open Channel"
echo "******************************"
echo ""
echo "COMMAND LINE: "
echo $command
echo ""
echo "RESULT:"

# execute command
result=$($command 2>$_error)
error=`cat ${_error}`

#echo "result(${result})"
#echo "error(${error})"

if [ ${#error} -gt 0 ]; then
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "FAIL"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "${error}"
else
  echo "******************************"
  echo "WIN"
  echo "******************************"
  echo "${result}"
  echo ""
  echo "Whats next? --> You need to wait 6 confirmations, for the channel to be ready."
  fundingTX=$(echo "${result}" | grep 'funding_txid' | cut -d '"' -f4)
  if [ "${network}" = "bitcoin" ]; then
    if [ "${chain}" = "main" ]; then
        echo "https://blockexplorer.com/tx/${fundingTX}"
    else
        echo "https://testnet.blockexplorer.com/tx/${fundingTX}"
    fi
  fi
  if [ "${network}" = "litecoin" ]; then
    echo "https://live.blockcypher.com/ltc/tx/${fundingTX}/"
  fi
fi
echo ""