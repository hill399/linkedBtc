let LinkedBtc = artifacts.require('LinkedBtc')
let LinkToken = artifacts.require('LinkToken')
let Oracle = artifacts.require('Oracle')
let LbtcToken = artifacts.require("./lbtcToken.sol");

module.exports = (deployer, network) => {

  const defaultMinWithdraw = 1000;
  // Local (development) networks need their own deployment of the LINK
  // token and the Oracle contract
  if (!network.startsWith('live')) {
    deployer.deploy(LinkToken).then(() => {
      return deployer.deploy(Oracle, LinkToken.address).then(() => {
        return deployer.deploy(LbtcToken, "LBTCToken", "LBTC", 8).then(() => {
          return deployer.deploy(LinkedBtc, LinkToken.address, defaultMinWithdraw, LbtcToken.address);
        })
      })
    })
  } else {
    // For live networks, use the 0 address to allow the ChainlinkRegistry
    // contract automatically retrieve the correct address for you
    deployer.deploy(LinkedBtc, '0x0000000000000000000000000000000000000000', defaultMinWithdraw)
  }
}
