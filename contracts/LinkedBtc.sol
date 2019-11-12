pragma solidity ^0.4.24;

import "chainlink/contracts/Chainlinked.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

interface ERC20 {
    function totalSupply() public view returns (uint supply);
    function balanceOf(address _owner) public view returns (uint balance);
    function transfer(address _to, uint _value) public returns (bool success);
    function transferFrom(address _from, address _to, uint _value) public returns (bool success);
    function approve(address _spender, uint _value) public returns (bool success);
    function allowance(address _owner, address _spender) public view returns (uint remaining);
    function decimals() public view returns(uint digits);
    event Approval(address indexed _owner, address indexed _spender, uint _value);
}

/// @title LinkedBTC Main Contract
/// @author hill399 (https://github.com/hill399)
/// @notice Ethereum contract to wrap/unwrap BTC on Ethereum
contract LinkedBtc is Chainlinked, Ownable {

  /* TODO: Fix SafeMath bugs and reimplement */

  uint256 constant private ORACLE_PAYMENT = 1 * LINK;

  event LbtcDeposited(
    address depositEthAddress,
    uint256 depositToken
  );

  event LbtcWithdrawal(
    address withdrawEthAddress,
    uint256 withdrawToken
  );

  event LinkDeposited(
    address depositEthAddress,
    uint256 depositToken
  );

  event LinkWithdrawal(
    address withdrawEthAddress,
    uint256 withdrawToken
  );

  event UserRegistered(
    address indexed newUser,
    uint256 timestamp
  );

  event RequestUserDeposit(
    bytes32 indexed requestId,
    address userAddress,
    string  btcTxId
  );

  event FulfillUserDeposit(
    bytes32 indexed requestId,
    address userAddress,
    bytes32 indexed txHash
  );

  event RequestValidateUser(
    bytes32 indexed requestId,
    address userAddress,
    string  btcTxId
  );

  event FulfillValidateUser(
    bytes32 indexed requestId,
    address userAddress,
    bytes32 indexed txHash
  );

  event RequestSendTransaction(
    bytes32 indexed requestId,
    string indexed btcAddress,
    uint256 btcValue
  );

  event FulfillSendTransaction(
    bytes32 indexed requestId
  );

  struct userStruct {
    string  btcAddress;
    uint256 btcBalance;
    uint256 btcHoldingBalance;
    bool validationState;
    uint256 linkBalance;
  }

  struct multiOracle {
    bytes32 jobId;
    address oracleAddress;
  }

  mapping(address => userStruct) public userAccounts;
  mapping(bytes32 => address) public requestToEthAddress;

  mapping(string => address) btcToEthAddress;
  mapping(string => bool) burntBTCTxs;

  uint256 public minimumWithdrawValue;

  address lbtcTokenAddress;
  address linkTokenAddress;

  string public transactionHash;

  multiOracle[] public nodeArray;

  bytes32 public tempRequest;
  bytes32[] public tempRequestId;

  /// @notice Contract constructor.
  /// @param _token Deployed LINK token address.
  /// @param _minWithdraw Minimum sat withdraw amount.
  /// @param _lbtcTokenAddress Deployed LBTC token address.
  constructor(address _token, uint256 _minWithdraw, address _lbtcTokenAddress)
  public {

    if (_token == address(0)) {
      setPublicChainlinkToken();
    } else {
      setLinkToken(_token);
    }

    minimumWithdrawValue = _minWithdraw;
    lbtcTokenAddress = _lbtcTokenAddress;
    linkTokenAddress = _token;
  }

  /// @notice Modifier to determine if BTC TXID has been used before.
  /// @param _txId BTC TXID to query against.
  modifier checkBurntTxs(string _txId){
    require(burntBTCTxs[_txId] == false, "Transaction has already been burnt");
    _;
  }

  /// @notice Modifier to determine if user has validated their BTC address.
  /// @param _status Boolean account state to query against.
  modifier checkUserState(bool _status){
    require(userAccounts[msg.sender].validationState == _status, "Invalid account state for this function");
    _;
  }

  /// @notice Modifier to ensure user has enough funds deposited against BTC address.
  /// @param _transferValue Requested sat value to transfer.
  modifier validateUserFunds(uint256 _transferValue){
    require(userAccounts[msg.sender].btcBalance >= _transferValue, "Insufficient User Balance");
    require(_transferValue >= minimumWithdrawValue, "Withdrawal amount too low");
    _;
  }

  /// @notice Modifier to determine if a BTC TXID is already being processed by CL node.
  modifier checkNoTxQueue() {
    require(userAccounts[msg.sender].btcHoldingBalance == 0, "Already processing TX for this user");
    _;
  }

  /// @notice Push CL oracle and JobID to add to aggregation.
  /// @dev One job per oracle only.
  /// @param _oracleAddress Depoloyed CL co-ordinator address.
  /// @param _jobId JobID from CL node.
  function pushNodeArray(string _jobId, address _oracleAddress)
  public
  onlyOwner
  {
    for (uint i=0; i<nodeArray.length; i++) {
      require(nodeArray[i].oracleAddress != _oracleAddress, "Oracle already registered");
    }
    nodeArray.push(multiOracle(stringToBytes32(_jobId), _oracleAddress));
  }

  /// @notice Request to unwrap LBTC onto BTC chain.
  /// @dev Balance determine by wrapping of BTC or depositing of LBTC.
  /// @param _btcAddress Native BTC address to send funds to.
  /// @param _txValue Value of transfer in sats.
  function requestSendTransaction(string _btcAddress, uint256 _txValue)
  checkUserState(true)
  validateUserFunds(_txValue)
  public {
    for(uint i=0; i < 3; i++){
        setOracle(nodeArray[i].oracleAddress);
        Chainlink.Request memory req = newRequest(nodeArray[i].jobId, this, this.fulfillSendTransaction.selector);
        string[] memory params = new string[](2);
        params[0] = _btcAddress;
        params[1] = uint2str(_txValue);
        req.add("function", "transaction");
        req.addStringArray("params", params);
        req.add("copyPath", "txHash");
        bytes32 requestId = chainlinkRequest(req, ORACLE_PAYMENT);
        tempRequestId.push(requestId);
    }

    userAccounts[msg.sender].btcBalance = userAccounts[msg.sender].btcBalance - _txValue;
    emit RequestSendTransaction(requestId, _btcAddress, _txValue);
  }

  /// @notice CL node response to transaction request.
  /// @dev Callback function configured in newRequest call.
  /// @dev Can only be called by CL node.
  /// @param _requestId ID of CL Node request.
  function fulfillSendTransaction(bytes32 _requestId)
  public
  recordChainlinkFulfillment(_requestId)
  {
    emit FulfillSendTransaction(_requestId);
  }


  /// @notice Function to wrap BTC funds into LBTC for ETH usage.
  /// @dev TXID will be burned once this function is called.
  /// @dev Deposit value in sats.
  /// @param _btcTxId Native BTC TXID.
  /// @param _depositValue BTC Deposit value in sats.
  function requestUserDeposit(string _btcTxId, uint256 _depositValue)
  checkBurntTxs(_btcTxId)
  checkUserState(true)
  checkNoTxQueue()
  public {
    setOracle(nodeArray[0].oracleAddress);
    Chainlink.Request memory req = newRequest(nodeArray[0].jobId, this, this.fulfillUserDeposit.selector);
    string[] memory params = new string[](3);
    params[0] = _btcTxId;
    params[1] = userAccounts[msg.sender].btcAddress;
    params[2] = uint2str(_depositValue);
    req.add("function", "deposit");
    req.addStringArray("params", params);
    req.add("copyPath", "txValid");
    bytes32 requestId = chainlinkRequest(req, ORACLE_PAYMENT);
    burntBTCTxs[_btcTxId] = true;

    userAccounts[msg.sender].btcHoldingBalance = _depositValue;

    bytes32 requestTemp = keccak256(abi.encodePacked(_btcTxId, userAccounts[msg.sender].btcAddress, uint2str(userAccounts[msg.sender].btcHoldingBalance)));
    requestToEthAddress[requestTemp] = msg.sender;
    emit RequestUserDeposit(requestId, msg.sender, _btcTxId);
  }

  /// @notice CL node response to deposit request.
  /// @dev Callback function configured in newRequest call.
  /// @dev Can only be called by CL node.
  /// @dev Retuns a hash based upon the one generated in the contract request (keccak256). Must match.
  /// @param _requestId CL ID of the requestUserDeposit call.
  /// @param _returnHash keccak256 generated at CL node to validate matching deposit.
  function fulfillUserDeposit(bytes32 _requestId, bytes32 _returnHash)
  public
  recordChainlinkFulfillment(_requestId)
  {
    if(requestToEthAddress[_returnHash] != address(0)){
        uint256 tempStandbyBalance = userAccounts[requestToEthAddress[_returnHash]].btcHoldingBalance;
        userAccounts[requestToEthAddress[_returnHash]].btcBalance = userAccounts[requestToEthAddress[_returnHash]].btcBalance + tempStandbyBalance;
        userAccounts[requestToEthAddress[_returnHash]].btcHoldingBalance = 0;

        emit FulfillUserDeposit(_requestId, requestToEthAddress[_returnHash], _returnHash);
    }
  }

  /// @notice Register a native BTC against an Ethereum account.
  /// @dev Once BTC Address per ETH address.
  /// @param _btcAddress BTC Address string.
  function registerUser(string _btcAddress)
  public
  returns (uint256)
  {
    // TODO: Requires better checks to link accounts.
    require(btcToEthAddress[_btcAddress] == address(0), "Address is already registered");
    uint256 validationRand = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % (10 ** 4);
    userAccounts[msg.sender] = userStruct({btcAddress:_btcAddress, btcBalance: 0, btcHoldingBalance: validationRand, validationState: false, linkBalance: 0});
    btcToEthAddress[_btcAddress] = msg.sender;
    return userAccounts[msg.sender].btcHoldingBalance;

    emit UserRegistered(msg.sender, now);
  }

  /// @notice Function to validate user BTC address.
  /// @dev Variation on the requestUserDeposit function, to fix holding balance value.
  /// @param _btcTxId Native BTC transaction which shows deposit of fixed holding balance.
  function requestValidateUser(string _btcTxId)
  checkUserState(false)
  public
  {
    setOracle(nodeArray[0].oracleAddress);
    Chainlink.Request memory req = newRequest(nodeArray[0].jobId, this, this.fulfillValidateUser.selector);
    string[] memory params = new string[](3);
    params[0] = _btcTxId;
    params[1] = userAccounts[msg.sender].btcAddress;
    params[2] = uint2str(userAccounts[msg.sender].btcHoldingBalance);
    req.add("function", "deposit");
    req.addStringArray("params", params);
    req.add("copyPath", "txValid");
    bytes32 requestId = chainlinkRequest(req, ORACLE_PAYMENT);
    burntBTCTxs[_btcTxId] = true;

    bytes32 requestTemp = keccak256(abi.encodePacked(_btcTxId, userAccounts[msg.sender].btcAddress, uint2str(userAccounts[msg.sender].btcHoldingBalance)));
    tempRequest = requestTemp;
    requestToEthAddress[requestTemp] = msg.sender;
    emit RequestValidateUser(requestId, msg.sender, _btcTxId);
  }

  /// @notice CL node response to validate request.
  /// @dev Callback function configured in validateUser call.
  /// @dev Can only be called by CL node.
  /// @dev Retuns a hash based upon the one generated in the contract request (keccak256). Must match.
  /// @param _requestId CL ID of the requestValidateUser call.
  /// @param _returnHash keccak256 generated at CL node to validate matching deposit.
  function fulfillValidateUser(bytes32 _requestId, bytes32 _returnHash)
  public
  recordChainlinkFulfillment(_requestId)
  {
    if(requestToEthAddress[_returnHash] != address(0)){
        uint256 tempStandbyBalance = userAccounts[requestToEthAddress[_returnHash]].btcHoldingBalance;
        userAccounts[requestToEthAddress[_returnHash]].btcBalance = userAccounts[requestToEthAddress[_returnHash]].btcBalance + tempStandbyBalance;
        userAccounts[requestToEthAddress[_returnHash]].btcHoldingBalance = 0;
        userAccounts[requestToEthAddress[_returnHash]].validationState = true;
        emit FulfillValidateUser(_requestId, requestToEthAddress[_returnHash], _returnHash);
    }
  }

  /// @notice Function to cancel CL request.
  /// @param _requestId of cancelled request.
  /// @param _payment of cancelled request.
  /// @param _callbackFunctionId of cancelled request.
  /// @param _expiration of cancelled request.
  function cancelRequest(bytes32 _requestId, uint256 _payment, bytes4 _callbackFunctionId, uint256 _expiration)
  public
  onlyOwner
  {
    cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
  }

  /// @notice Deposit LBTC token to account.
  /// @dev Must deposit using this function to track account funds.
  /// @param _depositToken Amount to deposit.
  function userDepositLbtc(uint256 _depositToken)
  checkUserState(true)
  public
  payable
  {
    require(ERC20(lbtcTokenAddress).transferFrom(msg.sender, address(this), _depositToken), "Tokens are unapproved for transfer");
    userAccounts[msg.sender].btcBalance = userAccounts[msg.sender].btcBalance + _depositToken;
    emit LbtcDeposited(msg.sender, _depositToken);
  }

  /// @notice Withdraw LBTC token from account.
  /// @dev Must withdraw using this function to track account funds.
  /// @param _withdrawToken Amount to withdraw.
  function userWithdrawLbtc(address _toAddress, uint256 _withdrawToken)
  checkUserState(true)
  validateUserFunds(_withdrawToken)
  public
  {
    require(ERC20(lbtcTokenAddress).transfer(_toAddress, _withdrawToken), "Unable to transfer tokens");
    userAccounts[msg.sender].btcBalance = userAccounts[msg.sender].btcBalance - _withdrawToken;
    emit LbtcWithdrawal(msg.sender, _withdrawToken);
  }

  /// @notice Deposit LINK token to account.
  /// @dev Must deposit using this function to track account funds.
  /// @param _depositToken Amount to deposit.
  function userDepositLink(uint256 _depositToken)
  public
  payable
  {
    require(bytes(userAccounts[msg.sender].btcAddress).length != 0, "User has not registered");
    require(ERC20(linkTokenAddress).transferFrom(msg.sender, address(this), _depositToken), "Tokens are unapproved for transfer");
    userAccounts[msg.sender].linkBalance = userAccounts[msg.sender].linkBalance + _depositToken;
    emit LinkDeposited(msg.sender, _depositToken);
  }

  /// @notice Withdraw LINK token from account.
  /// @dev Must withdraw using this function to track account funds.
  /// @param _withdrawToken Amount to withdraw.
  function userWithdrawLink(address _toAddress, uint256 _withdrawToken)
  checkUserState(true)
  validateUserFunds(_withdrawToken)
  public
  {
    require(ERC20(linkTokenAddress).transfer(_toAddress, _withdrawToken), "Unable to transfer tokens");
    userAccounts[msg.sender].linkBalance = userAccounts[msg.sender].linkBalance - _withdrawToken;
    emit LinkWithdrawal(msg.sender, _withdrawToken);
  }

  /// @dev Fallback function to allow token deposits.
  function()
  external
  payable
  {
      // To allow for erc20 deposits
  }


// BELOW IS HELPERS & TEST GETTERS TO CIRCUMVENT TRUFFLE TEST ISSUES

  /// @notice Convert string to bytes32 form.
  /// @dev Helper function.
  /// @param _stringIn string to convert
  function stringToBytes32(string memory _stringIn)
  internal
  pure
  returns (bytes32 result)
  {
    bytes memory tempEmptyStringTest = bytes(_stringIn);
    if (tempEmptyStringTest.length == 0) {
      return 0x0;
    }

    assembly { // solhint-disable-line no-inline-assembly
      result := mload(add(_stringIn, 32))
    }
  }

  /// @notice Convert uint to string form.
  /// @dev helper function.
  /// @param _i uint integer to convert.
  function uint2str(uint _i)
  public
  pure
  returns (string memory _uintAsString)
  {
    if (_i == 0) {
        return "0";
    }
    uint j = _i;
    uint len;
    while (j != 0) {
        len++;
        j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint k = len - 1;
    while (_i != 0) {
        bstr[k--] = byte(uint8(48 + _i % 10));
        _i /= 10;
    }
    return string(bstr);
  }

  /// @notice Check if BTC TX has been burnt.
  /// @dev Burn occurs when requestUserDeposit/requestValidateUser is called.
  /// @param _btcTxId ID to check burn state.
  function showBurntTxs(string _btcTxId)
  public
  view
  returns (bool)
  {
    return burntBTCTxs[_btcTxId];
  }

  /// @notice Returns linked ETH address when passed BTC address.
  /// @param _inAddress Native BTC address.
  function showbtcToEthAddress(string _inAddress)
  public
  view
  returns (address)
  {
    return btcToEthAddress[_inAddress];
  }

  /// @notice Getter to display user account data.
  /// @dev Debug use mostly, will be removed in later revisions.
  function showUserAccount()
  public
  view
  returns (string, uint256, uint256, bool)
  {
    return (userAccounts[msg.sender].btcAddress, userAccounts[msg.sender].btcBalance, userAccounts[msg.sender].btcHoldingBalance, userAccounts[msg.sender].validationState);
  }

}
