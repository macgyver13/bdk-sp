#!/usr/bin/env bash

########################### STAGE 1: setup ####################################

# 1. Ensure you have nix on your $PATH
which nix || curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --determinate
# 2. Create a user local configuration directory for nix
mkdir -p ~/.config/nix
# 3. Once you have nix installed enable nix flakes
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
# 4. Launch workshop environment.
nix develop .
# 5. Check bitcoind is running on regtest
regtest-cli getblockchaininfo
# 6. Check bdk-cli wallet was created correctly
regtest-bdk balance
# 7. Check sp-cli wallet was created correctly
regtest-sp balance
# 8. Synchronize bdk-cli wallet
regtest-bdk sync

###################### STAGE 2: fund bdk-cli wallet ###########################

# 9. Get a new address from bdk-cli wallet
REGTEST_ADDRESS=$(regtest-bdk unused_address | jq -r '.address' | tr -d '\n')
# 10. Mine a few more blocks to fund the wallet
just mine 1 $REGTEST_ADDRESS
# 11. Mine some of them to the internal wallet to confirm the bdk-cli balance
just mine 101
# 12. Synchronize bdk-cli wallet
regtest-bdk sync
# 13. Check balance
regtest-bdk balance

################ STAGE 3: create a silent payment output ######################

# 14. Get a silent payment code from sp-cli2 wallet
SP_CODE=$(regtest-sp code | jq -r '.silent_payment_code' | tr -d '\n')
# 15. Create a transaction spending bdk-cli wallet UTXOs to a the previous silent payment code
RAW_TX=$(regtest-bdk create_sp_tx --to-sp $SP_CODE:10000 --fee_rate 5 | jq -r '.raw_tx' | tr -d '\n')
# Add a OP_RETURN if you want
# OP_RETURN="Spending to silent payment UTXOs using BDK 🚀
# RAW_TX=$(regtest-bdk create-sp-tx --to-sp $SP_CODE:10000 --fee 5 --add_string $OP_RETURN)
# 16. Broadcast transaction using bdk-cli wallet
TXID=$(regtest-bdk broadcast --tx $RAW_TX | jq -r '.txid' | tr -d '\n')
# 17. Mine a new block
just mine 1
# 18. Once the new transaction has been mined, synchronize bdk-cli wallet again
regtest-bdk sync

################## STAGE 4: find a silent payment output ######################

# 19. Now synchronize sp-cli2 wallet using RPC
regtest-sp scan-rpc
# 20. Check balance on sp-cli2 wallet
regtest-sp balance
# 21. Check balance on bdk-cli wallet
regtest-bdk balance

########## STAGE 5: fund a transaction with a silent payment output ###########

# 22. Get a new address from bdk-cli wallet
REGTEST_ADDRESS=$(regtest-bdk unused_address | jq -r '.address' | tr -d '\n')
# 23. Create new transaction with sp-cli2 spending silent payment outputs
SP_TX=$(regtest-sp new-tx --to $REGTEST_ADDRESS:5000 --fee-rate 5 -- $(printf '%q' $(cat .regtest_tr_xprv)) | jq -r '.tx' | tr -d '\n')
# Add a OP_RETURN if you want
# OP_RETURN="Spending to silent payment UTXOs using BDK 🚀
# SP_TX=$(regtest-sp new-tx --to $REGTEST_ADDRESS:5000 --data $OP_RETURN --fee_rate 5 | jq -r '.tx' | tr -d '\n')

############ STAGE 6: verify a silent payment change output ###################

# This transaction as it is created by a silent payment wallet should have
# derived a silent payment output to receive the change back. That output is
# derived from a labelled silent payment code with label 0, the default
# specified by BIP 352 for change.
# 24. Verify the change output has been correctly derived for $SP_TX
DERIVATION_ORDER=0
CHANGE_LABEL=0
EXPECTED_CHANGE_SPK=$(regtest-sp derive-sp-for-tx $DERIVATION_ORDER --label $CHANGE_LABEL --tx-hex $SP_TX | jq -r '.script_pubkey_hex' | tr -d '\n')
TX_OUTPUT_SPKS=$(regtest-cli decoderawtransaction $SP_TX | jq -r '.vout[].scriptPubKey.hex' | tr '\n' ' ' | tr -d '\n')
if [[ -n "$EXPECTED_CHANGE_SPK" ]] && [[ $TX_OUTPUT_SPKS == *$EXPECTED_CHANGE_SPK* ]]; then
  echo "Change output matches!";
else
  echo "Something went wrong...";
fi

################# STAGE 7: spend a silent payment output ######################

# 25. Broadcast transaction
SP_TXID=$(regtest-cli sendrawtransaction $SP_TX | tr -d '\n')
# 26. Mine a new block
just mine 1
# 27. Once the new transaction has been mined, synchronize bdk-cli wallet again
regtest-bdk sync
# 28. Now synchronize sp-cli2 wallet using RPC scanning
regtest-sp scan-rpc
# 29. Check bdk-cli wallet balance, should have 5000 sats more than last time we checked
regtest-bdk balance
# 30. Check sp-cli2 wallet balance, should have >5000 sats less than last time we checked
regtest-sp balance
# 31. Congratulations 🍻 , you have performed your first sat-round trip using silent payments on top of BDK!
