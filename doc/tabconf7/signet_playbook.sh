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
# 5. Check bitcoind is running on signet
signet-cli getblockchaininfo
# 6. Check bdk-cli wallet was created correctly
signet-bdk balance
# 7. Check sp-cli wallet was created correctly
signet-sp balance
# 8. Synchronize bdk-cli wallet
signet-bdk sync

###################### STAGE 2: fund bdk-cli wallet ###########################

# 9. Get a new address from bdk-cli wallet
SIGNET_ADDRESS=$(signet-bdk unused_address | jq -r '.address')
# 10. Encode the address as a QR code
echo $SIGNET_ADDRESS | tr -d '\n' | qrencode -d 90 -t utf8 -o -
# 11. Use `padawan` wallet, or whatever other signet wallet to fund the bdk-cli wallet
# 12. Wait for the next block
# 13. Once the new transaction has been mined, synchronize bdk-cli wallet again
signet-bdk sync

################ STAGE 3: create a silent payment output ######################

# 14. Get a silent payment code from sp-cli2 wallet
SP_CODE=$(signet-sp code | jq -r '.silent_payment_code' | tr -d '\n')
# 15. Create a transaction spending bdk-cli wallet UTXOs to the previous silent payment code
RAW_TX=$(signet-bdk create_sp_tx --to-sp $SP_CODE:10000 --fee_rate 5 | jq -r '.raw_tx' | tr -d '\n')
# Add a OP_RETURN if you want
# OP_RETURN="Spending to silent payment UTXOs using BDK 🚀
# RAW_TX=$(signet-bdk create_sp_tx --to-sp $SP_CODE:10000 --fee 5 --add_string $OP_RETURN)
# 16. Broadcast transaction using bdk-cli wallet
TXID=$(signet-bdk broadcast --tx $RAW_TX | jq -r '.txid' | tr -d '\n')
# 17. Wait for the next block
# 18. Once the new transaction has been mined, synchronize bdk-cli wallet again
signet-bdk sync

################## STAGE 4: find a silent payment output ######################

# 19. Now synchronize sp-cli2 wallet using compact block filter scanning
signet-sp scan-cbf "https://silentpayments.dev/blindbit/signet/" --extra-peer $EXTRA_PEER
# 20. Check balance on sp-cli2 wallet
signet-sp balance
# 21. Check balance on bdk-cli wallet
signet-bdk balance

########## STAGE 5: fund a transaction with a silent payment output ###########

# 22. Get a new address from bdk-cli wallet
SIGNET_ADDRESS=$(signet-bdk unused_address | jq -r '.address' | tr -d '\n')
# 23. Create new transaction with sp-cli2 spending silent payment outputs
SP_TX=$(signet-sp new-tx --to $SIGNET_ADDRESS:4300 --fee-rate 3 -- $TR_XPRV | jq -r '.tx' | tr -d '\n')
# Add a OP_RETURN if you want
# OP_RETURN="Spending to silent payment UTXOs using BDK 🚀
# SP_TX=$(signet-sp new-tx --to $SIGNET_ADDRESS:5000 --data $OP_RETURN --fee_rate 5 | jq -r '.tx' | tr -d '\n')

############ STAGE 6: verify a silent payment change output ###################

# This transaction as it is created by a silent payment wallet should have
# derived a silent payment output to receive the change back. That output is
# derived from a labelled silent payment code with label 0, the default
# specified by BIP 352 for change.
# 24. Verify the change output has been correctly derived for $SP_TX
DERIVATION_ORDER=0
CHANGE_LABEL=0
EXPECTED_CHANGE_SPK=$(signet-sp derive-sp-for-tx $DERIVATION_ORDER --label $CHANGE_LABEL --tx-hex $SP_TX | jq -r '.script_pubkey_hex' | tr -d '\n')
TX_OUTPUT_SPKS=$(signet-cli decoderawtransaction $SP_TX | jq -r '.vout[].scriptPubKey.hex' | tr '\n' ' ' | tr -d '\n')
if [[ -n "$EXPECTED_CHANGE_SPK" ]] && [[ $TX_OUTPUT_SPKS == *$EXPECTED_CHANGE_SPK* ]]; then
  echo "Change output matches!";
else
  echo "Something went wrong...";
fi

################# STAGE 7: spend a silent payment output ######################

# 25. Broadcast transaction
SP_TXID=$(signet-cli sendrawtransaction $SP_TX | tr -d '\n')
# 26. Wait for the next block
# 27. Once the new transaction has been mined, synchronize bdk-cli wallet again
signet-bdk sync
# 28. Now synchronize sp-cli2 wallet using compact block filter scanning
signet-sp scan-cbf "https://silentpayments.dev/blindbit/"
# 29. Check bdk-cli wallet balance, should have 5000 sats more than last time we checked
signet-bdk balance
# 30. Check sp-cli2 wallet balance, should have >5000 sats less than last time we checked
signet-sp balance
# 31. Congratulations 🍻 , you have performed your first sat-round trip using silent payments on top of BDK!
