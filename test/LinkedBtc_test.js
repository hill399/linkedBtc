'use strict'

// eslint-disable-next-line @typescript-eslint/no-var-requires
const h = require('chainlink-test-helpers')
const truffleAssert = require('truffle-assertions');

contract('LinkedBtc', accounts => {
  const LinkToken = artifacts.require('lib/LinkToken.sol')
  const Oracle = artifacts.require('lib/Oracle.sol')
  const LinkedBtc = artifacts.require('LinkedBtc.sol')
  const LbtcToken = artifacts.require('lbtcToken.sol')

  const defaultAccount = accounts[0]
  const stranger = accounts[1]
  const consumer = accounts[2]
  const oracleNode = accounts[3]

  const jobId = '4c7b7ffb66b344fbaa64995af81e355a'

  // Represents 1 LINK for testnet requests
  const payment = web3.utils.toWei('1')
  const defaultWithdraw = 1000;
  const userBTCAddress = "mo83FzMwaZD7Sw8dYbhsr7a529vf2Q3mwR";
  const strangerBTCAddress = "2o83FzMwaZD7Sw8dYbhsr7a529vf2Q3mwR";
  const btcTxId = "a646600eca3920eebaba8ab053f38d2bc8074d9550e6984f7d3b36e95ecfba97";

  const lbtcTotalSupply = 21000000;

  const consumerTokenBalance = 10000;
  const strangerTokenBalance = 2000;

  let link, oc1, oc2, oc3, cc, tc
  let userData
  let requestPack, requestId, request, tx

  beforeEach(async () => {
    link = await LinkToken.new()

    oc1 = await Oracle.new(link.address, { from: defaultAccount })
    oc2 = await Oracle.new(link.address, { from: defaultAccount })
    oc3 = await Oracle.new(link.address, { from: defaultAccount })

    await oc1.setFulfillmentPermission(oracleNode, true, { from: defaultAccount })
    await oc2.setFulfillmentPermission(oracleNode, true, { from: defaultAccount })
    await oc3.setFulfillmentPermission(oracleNode, true, { from: defaultAccount })

    tc = await LbtcToken.new("LBTCToken", "LBTC", 8, { from: defaultAccount })
    cc = await LinkedBtc.new(link.address, defaultWithdraw, tc.address, { from: defaultAccount })

    await cc.registerUser(userBTCAddress, {from: consumer});
    userData = await cc.userAccounts.call(consumer);
//  userData = [string  btcAddress; uint256 btcBalance; uint256 btcHoldingBalance; bool validationState;]

//  Code to deploy full lbtc allowance to contract
    await tc.mint(defaultAccount, lbtcTotalSupply);
    let balance = await tc.balanceOf(defaultAccount)
    await tc.transfer(cc.address, balance - (consumerTokenBalance + strangerTokenBalance), {from: defaultAccount})

    await tc.transfer(consumer, consumerTokenBalance, {from: defaultAccount})
    await tc.transfer(stranger, strangerTokenBalance, {from: defaultAccount})

    await link.transfer(stranger, web3.utils.toWei('5', 'ether'))
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
          cc.pushNodeArray(jobId, oc1.address, {from: stranger}),
        );
        await cc.pushNodeArray(jobId, oc1.address, {from: defaultAccount});
      })

      it('Able to add a new node', async () => {
        await cc.pushNodeArray(jobId, oc1.address, {from: defaultAccount});
        let nodeArrayZero = await cc.nodeArray.call(0)
        assert.equal(nodeArrayZero.oracleAddress, oc1.address, "Oracle address wasn't stored correctly");
      })

      it('Cannot add the same oracle address twice', async () => {
        await cc.pushNodeArray(jobId, oc1.address, {from: defaultAccount});
        await truffleAssert.reverts(
          cc.pushNodeArray(jobId, oc1.address, {from: defaultAccount}),
          "Oracle already registered");
        })
      })
  })

  describe('#Validate User', () => {
    beforeEach(async () => {
      await cc.pushNodeArray(jobId, oc1.address, {from: defaultAccount});
    })

    context('Request Without LINK', () => {
      it('Reverts', async () => {
        await h.assertActionThrows(async () => {
          await cc.requestValidateUser(btcTxId, {from: consumer})
        })
      })
    })

    context('Request With LINK', () => {
      beforeEach(async () => {
        await link.transfer(cc.address, web3.utils.toWei('1', 'ether'))
        tx = await cc.requestValidateUser(btcTxId, {from: consumer})
      })

      it('Triggers a log event in the Oracle contract', async () => {
        request = h.decodeRunRequest(tx.receipt.rawLogs[3])
        requestId = request.id
        assert.equal(oc1.address, tx.receipt.rawLogs[3].address)
        assert.equal(
          request.topic,
          web3.utils.keccak256(
            'OracleRequest(bytes32,address,bytes32,uint256,address,bytes4,uint256,uint256,bytes)',
          ),
        )
      })

      it('Adds the validate request to the requestToEthAddress mapping', async () => {
        // Add code to match solidity keccak encode in JS
        requestPack = await cc.tempRequest.call();
        let tempAddress = await cc.requestToEthAddress(requestPack);
        assert.equal(consumer, tempAddress);
      })

      it('Burns the submitted BTC Tx', async () => {
        let compBurnAddress = await cc.showBurntTxs(btcTxId);
        assert.equal(compBurnAddress, true);
      })
    })

    context('Fulfill Validation', () => {
      beforeEach(async () => {
        await link.transfer(cc.address, web3.utils.toWei('1', 'ether'))
        tx = await cc.requestValidateUser(btcTxId, {from: consumer})
        requestPack = await cc.tempRequest.call();
        request = h.decodeRunRequest(tx.receipt.rawLogs[3])
        await h.fulfillOracleRequest(oc1, request, requestPack, { from: oracleNode })
        userData = await cc.userAccounts.call(consumer);
      })

      it('Updates holding balance when matching hash is returned from node', async () => {
        assert(userData[1] > 0, "Holding balance has not been moved into user account");
      })

      it('Clears the holding balance when validated', async () => {
        assert.equal(userData[2], 0, "Holding balance has not been zero'd");
      })

      it('Validates the user account', async () => {
        assert.equal(userData[3], true, "User has not been validated");
      })
    })
  })

  describe('#Unwrap BTC Funds', () => {
    beforeEach(async () => {
      await cc.pushNodeArray(jobId, oc1.address, {from: defaultAccount});
      await cc.pushNodeArray(jobId, oc2.address, {from: defaultAccount});
      await cc.pushNodeArray(jobId, oc3.address, {from: defaultAccount});
      await link.transfer(cc.address, web3.utils.toWei('1', 'ether'))
      tx = await cc.requestValidateUser(btcTxId, {from: consumer})
      requestPack = await cc.tempRequest.call();
      request = h.decodeRunRequest(tx.receipt.rawLogs[3])
      await h.fulfillOracleRequest(oc1, request, requestPack, { from: oracleNode })

      let depositBalance = 1000
      await tc.approve(cc.address, depositBalance, {from: consumer})
      await cc.userDepositLbtc(depositBalance, {from: consumer})
    })

    context('Request Without LINK', () => {
      it('Reverts', async () => {
        await h.assertActionThrows(async () => {
          await cc.requestValidateUser(btcTxId, {from: consumer})
        })
      })
    })

    context('Request With LINK', () => {
      beforeEach(async () => {
        await link.transfer(cc.address, web3.utils.toWei('3', 'ether'))
        userData = await cc.userAccounts.call(consumer);
        tx = await cc.requestSendTransaction(userBTCAddress, defaultWithdraw, {from: consumer})
      })

      context('Oracle 1', () => {
        it('Triggers a log event in the Oracle 1 contract', async () => {
          request = h.decodeRunRequest(tx.receipt.rawLogs[3])
          requestId = request.id
          assert.equal(oc1.address, tx.receipt.rawLogs[3].address)
          assert.equal(
            request.topic,
            web3.utils.keccak256(
              'OracleRequest(bytes32,address,bytes32,uint256,address,bytes4,uint256,uint256,bytes)',
            ),
          )
        })
      })

      context('Oracle 2', () => {
        /* Expand these tests to review tx logs */
        it('Job request is made to Oracle 2', async () => {
          let jobRequest2 = await cc.tempRequestId.call(1)
          assert(jobRequest2 > null, "Job 2 not published")
        })
      })

      context('Oracle 3', () => {
        /* Expand these tests to review tx logs */
        it('Job request is made to Oracle 3', async () => {
          let jobRequest3 = await cc.tempRequestId.call(2)
          assert(jobRequest3 > null, "Job 3 not published")
        })
      })

      it('Deducts the transfer balance of sender', async () => {
        let postSendBal = await cc.userAccounts.call(consumer);
        assert.equal(Number(userData[1]) - defaultWithdraw, postSendBal[1], "User balance not reduced on send transaction");
      })
    })

    context('Fulfill Send Transaction', () => {
      beforeEach(async () => {
        await link.transfer(cc.address, web3.utils.toWei('3', 'ether'))
        userData = await cc.userAccounts.call(consumer);
        tx = await cc.requestSendTransaction(userBTCAddress, defaultWithdraw, {from: consumer})
        request = h.decodeRunRequest(tx.receipt.rawLogs[3])
        await h.fulfillOracleRequest(oc1, request, { from: oracleNode })
        userData = await cc.userAccounts.call(consumer);
      })
    })
/*
    Solidity code to be modified to allow BTC Tx ID to be returned

      it('Returns a BTC TXID if successful', async () => {
        assert(userData[1] > 0, "Holding balance has not been moved into user account");
      })
*/
  })

  describe('#Token Operations', () => {
    beforeEach(async () => {
      await cc.pushNodeArray(jobId, oc1.address, {from: defaultAccount});
      await link.transfer(cc.address, web3.utils.toWei('1', 'ether'))
      tx = await cc.requestValidateUser(btcTxId, {from: consumer})
      requestPack = await cc.tempRequest.call();
      request = h.decodeRunRequest(tx.receipt.rawLogs[3])
      await h.fulfillOracleRequest(oc1, request, requestPack, { from: oracleNode })
      userData = await cc.userAccounts.call(consumer);
    })

    context('User Withdrawals', () => {
      it('Able to withdraw lbtc tokens from validated account', async () => {
        let withdrawBalance = Number(userData[1]) - 50
        await cc.userWithdrawLbtc(defaultAccount, withdrawBalance, {from: consumer});
        userData = await cc.userAccounts.call(consumer)
        assert.equal(50, Number(userData[1]))
      })

      it('Cannot withdraw less than minWithdraw', async () => {
        await truffleAssert.reverts(
          cc.userWithdrawLbtc(defaultAccount, defaultWithdraw - 1, {from: consumer}),
          "Withdrawal amount too low");
      })
    })

    context('User Deposits', () => {
      it('Able to deposit lbtc tokens to validated account', async () => {
        let depositBalance = 1000
        let preTransferBal = userData[1]
        await tc.approve(cc.address, depositBalance, {from: consumer})
        await cc.userDepositLbtc(depositBalance, {from: consumer})
        userData = await cc.userAccounts.call(consumer)
        let postTransferBal = userData[1]
        assert.equal(Number(preTransferBal) + depositBalance, Number(postTransferBal), "Tokens have not been correctly deposited")
      })

      it('Unable to deposit lbtc tokens to invalid account', async () => {
        let depositBalance = 1000
        await tc.approve(cc.address, depositBalance, {from: stranger})
        await truffleAssert.reverts(
          cc.userDepositLbtc(depositBalance, {from: stranger}),
          "Invalid account state for this function");
      })

      it('Able to deposit link tokens to registered & invalid account', async () => {
        let depositBalance = web3.utils.toWei('1', 'ether')
        await cc.registerUser(strangerBTCAddress, {from: stranger});
        await link.approve(cc.address, depositBalance , {from: stranger})
        await cc.userDepositLink(depositBalance, {from: stranger})
        let strangerData = await cc.userAccounts.call(stranger)
        assert.equal(strangerData[4], depositBalance, "User Link balance not updated")
      })

    })
  })
})
