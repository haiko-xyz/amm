# Set environment variables
export STARKNET_RPC=https://starknet-goerli.g.alchemy.com/v2/KDQIvQ6ANSkhkuP-9WP0P6f_eJLW6kHj
export DEPLOYER=0x01d589e33d4e8976725d62f8cb8bf99d1a1fb2789c79d76072625a4a556535d7
export OWNER=0x2afc579c1a02e4e36b2717bb664bee705d749d581e150d1dd16311e3b3bb057
export STARKNET_KEYSTORE=~/.starkli-wallets/deployer/testnet_deployer_keystore.json
export STARKNET_ACCOUNT=~/.starkli-wallets/deployer/testnet_deployer_account_starkli.json
export PRAGMA_ORACLE=0x620a609f88f612eb5773a6f4084f7b33be06a6fed7943445aebce80d6a146ba

# Deployments
# Staging (1 Nov 2023)
export MARKET_MANAGER_CLASS_HASH=0x701dc7c897cbf4073f9c97a63fa1465dd32291d0c74849833bc427bb2a3799
export MARKET_MANAGER=0x48c1140f9e9599bdc24d98f1895d913d841aedc30a8fec93f0efd90a2b6b7b9
export QUOTER_CLASS_HASH=0x114eb9aa0df8795895c709c28bc466ef727fd015c3a4d7c46b1412b1f79f7bd
export QUOTER=0x06f3afe508abfb5a7829409739c5f3a86f8b7f97d5b4f63dea272d78b842642f

# Declare contract classes
# MarketManager
sncast --url $STARKNET_RPC --keystore $STARKNET_KEYSTORE --account $STARKNET_ACCOUNT declare --contract-name MarketManager
# Quoter
sncast --url $STARKNET_RPC --keystore $STARKNET_KEYSTORE --account $STARKNET_ACCOUNT declare --contract-name Quoter

# Deploy contracts
# MarketManager
sncast --url $STARKNET_RPC --keystore $STARKNET_KEYSTORE --account $STARKNET_ACCOUNT deploy --class-hash $MARKET_MANAGER_CLASS_HASH --constructor-calldata $OWNER