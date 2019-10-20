pragma solidity ^0.4.24;

import "chainlink/contracts/Chainlinked.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

/* TODO: Introduce ERC20 component to release funds */

contract LinkedBtc is Chainlinked, Ownable {

  uint256 constant private ORACLE_PAYMENT = 1 * LINK;

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
  }

  struct multiOracle {
    bytes32 jobId;
    address oracleAddress;
  }

  mapping(address => userStruct) private userAccounts;
  mapping(bytes32 => address) private requestToEthAddress;

  mapping(string => address) private btcToEthAddress;
  mapping(string => bool) private burntBTCTxs;

  uint256 public minimumWithdrawValue;

  string public transactionHash;

  multiOracle[] public nodeArray;

  constructor(address _token, uint256 _minWithdraw)
  public {

    if (_token == address(0)) {
      setPublicChainlinkToken();
    } else {
      setLinkToken(_token);
    }

    minimumWithdrawValue = _minWithdraw;
  }

  modifier checkBurntTxs(string _txId){
    require(burntBTCTxs[_txId] == false, "Transaction has already been burnt");
    _;
  }

  modifier checkUserState(bool _status){
    require(userAccounts[msg.sender].validationState == _status, "Invalid account state for this function");
    _;
  }

  modifier validateUserFunds(uint256 _transferValue){
    require(userAccounts[msg.sender].btcBalance >= _transferValue, "Insufficient User Balance");
    require(_transferValue >= minimumWithdrawValue, "Withdrawal amount too low");
    _;
  }

  modifier checkNoTxQueue() {
    require(userAccounts[msg.sender].btcHoldingBalance == 0, "Already processing TX for this user");
    _;
  }

  function pushNodeArray(string _jobId, address _oracleAddress)
  public {
    nodeArray.push(multiOracle(stringToBytes32(_jobId), _oracleAddress));
  }

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
    }

    userAccounts[msg.sender].btcBalance = userAccounts[msg.sender].btcBalance - _txValue;
    emit RequestSendTransaction(requestId, _btcAddress, _txValue);
  }

  function fulfillSendTransaction(bytes32 _requestId)
  public
  recordChainlinkFulfillment(_requestId)
  {
    emit FulfillSendTransaction(_requestId);
  }

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


  function registerUser(string _btcAddress)
  public
  returns (uint256)
  {
    require(btcToEthAddress[_btcAddress] == address(0));
    uint256 validationRand = uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty))) % 9999;
    userAccounts[msg.sender] = userStruct({btcAddress: _btcAddress, btcBalance: 0, btcHoldingBalance: validationRand, validationState: false});
    btcToEthAddress[_btcAddress] = msg.sender;
    return userAccounts[msg.sender].btcHoldingBalance;

    emit UserRegistered(msg.sender, now);
  }

  function showUserValidationSats()
  public
  view
  returns (string, uint256, uint256, bool)
  {
    return (userAccounts[msg.sender].btcAddress, userAccounts[msg.sender].btcBalance, userAccounts[msg.sender].btcHoldingBalance, userAccounts[msg.sender].validationState);
  }


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
    requestToEthAddress[requestTemp] = msg.sender;
    emit RequestValidateUser(requestId, msg.sender, _btcTxId);
  }


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

  function cancelRequest(bytes32 _requestId, uint256 _payment, bytes4 _callbackFunctionId, uint256 _expiration)
  public
  onlyOwner
  {
    cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
  }

  function stringToBytes32(string memory source)
  internal
  pure
  returns (bytes32 result)
  {
    bytes memory tempEmptyStringTest = bytes(source);
    if (tempEmptyStringTest.length == 0) {
      return 0x0;
    }

    assembly { // solhint-disable-line no-inline-assembly
      result := mload(add(source, 32))
    }
  }

  function uint2str(uint _i)
  internal
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
}
