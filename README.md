# linkedBtc

## Overview
Concept implementation of wrapping BTC on Ethereum using Chainlink. Design consists of a chainlinked smart contract on Ethereum, an external adapter to handle send/receive/validate functions and a multisig BTC wallet generated through BlockCypher.

Currently operating on ETH-Ropsten/BTC-testnet3.

## Multisig wallet
To allow BTC deposits/withdrawals, a 2-of-3 multisig wallet is configured on the Bitcoin chain. Deposits are made directly into the multisig wallet, with withdrawals triggered by three seperate Chainlink nodes signing an outgoing transaction with their respective private keys. When a majority signing occurs, the transaction is proccessed by BlockCypher.

## Smart Contract
Allows a web3-enabled user to wrap/unwrap BTC funds tied to their BTC address.

### Address Registration
When registering an address, the user will receive a pseudo-random satoshi value for which they will need to deposit into the designated BTC wallet. The user provides the contract with a corresponding BTC TXID for which to validate against. This response is uniquely hashed and a Chainlink node request is made. If  successful and a matching hash is returned, the BTC address will be tied to the ETH address for further use.

### BTC User Deposit
Similar to address registration above, however the user can define deposit values once the BTC-ETH address link has been made.

### BTC User Withdrawal
To withdraw a BTC balance from the contract (i.e. balance unwrap), the user must specify an amount and destination address. Three seperate Chainlink requests are made to the nodes associated to the 2-of-3 multisig wallet. In this configuration, bad-actors would require 2/3 participation.

## External Adapter
A Go adapter has been written utilising the Linkpool Bridges framework to interface with the BlockCypher API and perform data hashing to determine validity of deposits. Each node will use the generic adapter (LBTC.go) but customise with a unique env variables (i.e. API, BTC Keys). Each node operator is the owner of 1 of 3 of the multisig and has the ability to respond to deposit queries and part-sign any outgoing transactions.

## Outstanding Work
```
- ERC20 token interface to allow free movement of wrapped funds
```
