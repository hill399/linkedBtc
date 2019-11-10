'use strict'

// eslint-disable-next-line @typescript-eslint/no-var-requires
const h = require('chainlink-test-helpers')
const truffleAssert = require('truffle-assertions');

contract('LinkedBtc', accounts => {
  const LinkToken = artifacts.require('lib/LinkToken.sol')
  const Oracle = artifacts.require('lib/Oracle.sol')
  const LinkedBtc = artifacts.require('LinkedBtc.sol')

  const defaultAccount = accounts[0]
  const oracleNode = accounts[1]
  const stranger = accounts[2]
  const consumer = accounts[3]

  const jobId = '4c7b7ffb66b344fbaa64995af81e355a'

  // Represents 1 LINK for testnet requests
  const payment = web3.utils.toWei('1')
  const defaultWithdraw = 1000;
  const userBTCAddress = "mo83FzMwaZD7Sw8dYbhsr7a529vf2Q3mwR";
  const btcTxId = "a646600eca3920eebaba8ab053f38d2bc8074d9550e6984f7d3b36e95ecfba97";

  let link, oc, cc
  let userData
  let requestPack
  let requestId

  beforeEach(async () => {
    link = await LinkToken.new()
    oc = await Oracle.new(link.address, { from: defaultAccount })
    cc = await LinkedBtc.new(link.address, defaultWithdraw, { from: defaultAccount })
    await oc.setFulfillmentPermission(oracleNode, true, {
      from: defaultAccount,
    })

    await cc.registerUser(userBTCAddress, {from: consumer});
    userData = await cc.userAccounts.call(consumer);
//  userData = [string  btcAddress; uint256 btcBalance; uint256 btcHoldingBalance; bool validationState;]
  })

  describe('#User Management', () => {
    context('New Account', () => {
      it('Stores input BTC address for user', async () => {
        assert.equal(userData[0], userBTCAddress, "BTC address wasn't stored correctly");
      })

      it('Generates a new pseudo-random deposit amount over 1000 sats', async() => {
        assert(userData[2] > 999, "Random deposit value is less than 1000 sats");
      })

      it('Cannot double-register a BTC address', async() => {
        await truffleAssert.reverts(
           cc.registerUser(userBTCAddress, {from: consumer}),
           "Address is already registered");
      })

      it('Initialises with a disabled account state', async() => {
        assert.equal(userData[3], false, "Address initialised in true state");
      })
    })

    context('User Deposits', () => {
      it('Cannot use the requestUserDeposit in disabled state', async() => {
        await truffleAssert.reverts(
          cc.requestUserDeposit("aabbccddee", 10, {from: consumer}),
          "Invalid account state for this function");
        })
      })
    })

  describe('#Contract Administration', () => {
    context('Node Management', () => {
      it('Only owner can add a new oracle', async () => {
        await truffleAssert.reverts(
          cc.pushNodeArray(jobId, oc.address, {from: stranger}),
        );
        await cc.pushNodeArray(jobId, oc.address, {from: defaultAccount});
      })

      it('Able to add a new node', async () => {
        await cc.pushNodeArray(jobId, oc.address, {from: defaultAccount});
        let nodeArrayZero = await cc.nodeArray.call(0)
        assert.equal(nodeArrayZero.oracleAddress, oc.address, "Oracle address wasn't stored correctly");
      })

      it('Cannot add the same oracle address twice', async () => {
        await cc.pushNodeArray(jobId, oc.address, {from: defaultAccount});
        await truffleAssert.reverts(
          cc.pushNodeArray(jobId, oc.address, {from: defaultAccount}),
          "Oracle already registered");
        })
      })
  })

  describe('#Validate User', () => {
    beforeEach(async () => {
      await cc.pushNodeArray(jobId, oc.address, {from: defaultAccount});
    })

    context('Request Without LINK', () => {
      it('Reverts', async () => {
        await h.assertActionThrows(async () => {
          await cc.requestValidateUser(btcTxId, {from: defaultAccount})
        })
      })
    })

    context('Request With LINK', () => {
      let request;
      let tx;

      beforeEach(async () => {
        await link.transfer(cc.address, web3.utils.toWei('1', 'ether'))
        tx = await cc.requestValidateUser(btcTxId, {from: defaultAccount})
      })

      context('Sending a request to the oracle', () => {
        it('Triggers a log event in the Oracle contract', async () => {
          request = h.decodeRunRequest(tx.receipt.rawLogs[3])
          requestId = request.id
          assert.equal(oc.address, tx.receipt.rawLogs[3].address)
          assert.equal(
            request.topic,
            web3.utils.keccak256(
              'OracleRequest(bytes32,address,bytes32,uint256,address,bytes4,uint256,uint256,bytes)',
            ),
          )
        })
        
/*
        it('Adds the validate request to the requestToEthAddress mapping', async () => {
          // Add code to match solidity keccak encode in JS
        })
*/

        it('Burns the submitted BTC Tx', async () => {
          let compBurnAddress = await cc.showBurntTxs(btcTxId);
          assert.equal(compBurnAddress, true);
        })
      })
    })
  })
})
