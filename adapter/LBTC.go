// Chainlink adapter for reading/writing transactions via BlockCypher API
// (https://www.blockcypher.com/dev/bitcoin/)
//
// Function: deposit - User provides TXID to smart contract, which is located using API to confirm.
// 		       Adapter returns hash of TXID, origin address and value using sha3 hashing.
//		       Hash will then be confirmed against hash stored in SC, and account credited if matched.
//
// Function: transaction - User will send destination address and tx value to 3 different Chainlink nodes, each
//			   of which can part-sign a multisig transaction of the multisig BTC locker. Once 2 of 3
//			   nodes have signed, BlockCypher API will collate and process transaction.

package main

import (
	"fmt"
	"log"
	"os"
	"github.com/blockcypher/gobcy"
	"github.com/joho/godotenv"
	"strconv"
	"errors"

	"github.com/linkpoolio/bridges/bridge"
	"github.com/miguelmota/go-solidity-sha3"
	"encoding/hex"
)

/* Global Variables */
var blockCypherApi string
var cTicker string
var cChain string
var cAccount string
var cPrivKey string

var cPubKey1 string
var cPubKey2 string
var cPubKey3 string

var numberConfirmations string

func init() {
	if err := godotenv.Load(); err != nil {
		log.Print("No .env file found")
	}

	var exists bool

	blockCypherApi, exists = os.LookupEnv("BLOCKCYPHER_API_KEY")
	cTicker, exists = os.LookupEnv("CRYPTO_TICKER")
	cChain, exists = os.LookupEnv("CRYPTO_CHAIN")
	cAccount, exists = os.LookupEnv("CRYPTO_ACCOUNT")
	cPrivKey, exists = os.LookupEnv("CRYPTO_PK")

	cPubKey1, exists = os.LookupEnv("PUBKEY_1")
	cPubKey2, exists = os.LookupEnv("PUBKEY_2")
	cPubKey3, exists = os.LookupEnv("PUBKEY_3")


	numberConfirmations, exists = os.LookupEnv("NUM_OF_CONF")

	if exists != true {
		log.Print(".env variables did not load correctly")
	}
}

type linkedbtc struct{}

/* Main function which takes parses function string to determine function */
/* function and parameters fed from SC */
func (cc *linkedbtc) Run(h *bridge.Helper) (interface{}, error) {
	f := h.Data.Get("function")
	param := h.Data.Get("params").Array()

	switch f.String() {
	case "deposit":		/* p0 = TXID , p1 = BTC Address , p2 = TX value */
		txValid, err := validateUserDeposit(param[0].String(), param[1].String(), param[2].String())
		return map[string]string{"txValid": txValid}, err

	case "transaction":  /* p0 = destAddress, p1 = TX Value */
		result, err := sendMultisigTransaction(param[0].String(), int(param[1].Int()))
		return map[string]string{"txHash": result}, err
	}

	return 0, errors.New("Invalid function called")
}

// Opts is the bridge.Bridge implementation
func (cc *linkedbtc) Opts() *bridge.Opts {
	return &bridge.Opts{
		Name:   "linkedbtc",
		Lambda: true,
	}
}

func main() {
	bridge.NewServer(&linkedbtc{}).Start(8080)
}


/* Function - sendMultisigTransaction */
/* Will part sign a multisig transaction with node private key*/
/* Transaction is fed back to BlockCypher, which will collate and process is 2-of-3 quorum is met */
func sendMultisigTransaction(sendAddress string, txvalue int) (string, error) {
  bcy := gobcy.API{blockCypherApi, cTicker, cChain}

  //use TempMultiTX to set up multisig
  temptx, err := gobcy.TempMultiTX("", sendAddress, txvalue, 2, []string{cPubKey1, cPubKey2, cPubKey3})

  if err != nil {
      fmt.Println(err)
      return "", err
  }

  //Then follow the New/Send two-step process with this temptx as the input
  skel, err := bcy.NewTX(temptx, false)
  //Sign it locally
  err = skel.Sign([]string{cPrivKey})
  if err != nil {
      fmt.Println(err)
      return "", err
  }

  //Send TXSkeleton
  skel, err = bcy.SendTX(skel)
  if err != nil {
      fmt.Println(err)
      return "", err
  }

  return skel.Trans.Hash, nil
}


/* Function -Validate User Registration */
/* SC will set random sat value for user to deposit into BTC wrap account */
/* Will return hash to validate back in SC */
func validateUserDeposit(txHash string, txAddress string, txValue string) (string, error) {
  var inputAddress string
  var inputValue string

  numberConfirmationsLocal, err :=  strconv.Atoi(numberConfirmations)
  if err != nil {
    fmt.Println(err)
  }

  params := map[string]string{
    "omitWalletAddresses": "true",
  }

  btc := gobcy.API{blockCypherApi, cTicker, cChain}
  addr, err := btc.GetAddrFull(cAccount, params)

  if err != nil {
    return "", err
  }

  for _, a := range addr.TXs {
  	if a.Hash == txHash {
		if (a.Confirmations >= numberConfirmationsLocal) {
			for _, b := range a.Inputs {
				inputAddress = b.Addresses[0]
			}

			for _, c := range a.Outputs {
				if c.Addresses[0] != inputAddress {
					inputValue = strconv.Itoa(c.Value)
				}
			}

			if ((txValue == inputValue) && (txAddress == inputAddress)) {
				hash := solsha3.SoliditySHA3(
				[]string{"string", "string", "string"},
				[]interface{}{txHash, txAddress, txValue},)
				hexstr := "0x" + hex.EncodeToString(hash)
				return hexstr, nil
			}

			} else {
				fmt.Println("Not enough confirmations to verify at this time\n")
			}
		}
	}

	return "", errors.New("Invalid TXID and/or TX value")
}
