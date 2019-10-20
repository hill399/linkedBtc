'use strict'

// eslint-disable-next-line @typescript-eslint/no-var-requires
const h = require('chainlink-test-helpers')

contract('LinkedBtc', accounts => {
  const LinkToken = artifacts.require('LinkToken.sol')
  const Oracle = artifacts.require('Oracle.sol')
  const LinkedBtc = artifacts.require('LinkedBtc.sol')

  const defaultAccount = accounts[0]
  const oracleNode = accounts[1]
  const stranger = accounts[2]
  const consumer = accounts[3]

  // These parameters are used to validate the data was received
  // on the deployed oracle contract. The Job ID only represents
  // the type of data, but will not work on a public testnet.
  // For the latest JobIDs, visit our docs here:
  // https://docs.chain.link/docs/testnet-oracles
  const jobId = web3.utils.toHex('4c7b7ffb66b344fbaa64995af81e355a')

  // Represents 1 LINK for testnet requests
  const payment = web3.utils.toWei('1')
  const defaultWithdraw = 1000;

  let link, oc, cc

  beforeEach(async () => {
    link = await LinkToken.new()
    oc = await Oracle.new(link.address, { from: defaultAccount })
    cc = await LinkedBtc.new(link.address, defaultWithdraw, { from: consumer })
    await oc.setFulfillmentPermission(oracleNode, true, {
      from: defaultAccount,
    })
  })

  describe('#registerUser', () => {
    const userBTCAddress = "mo83FzMwaZD7Sw8dYbhsr7a529vf2Q3mwR";
    let retAddress, retBalance, retHolding, retValid;

    context('new Account', () => {
      it('returns validation amount over defaultWithdraw', async () => {
        await cc.registerUser(userBTCAddress, {from: consumer});
        retAddress, retBalance, retHolding, retValid = await cc.showUserValidationSats();
        assert.equal(retAddress, userBTCAddress, "BTC address wasn't stored correctly");
      })
    })
  })
})
