pragma solidity ^0.4.24;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20Pausable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Capped.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Detailed.sol";

contract lbtcToken is ERC20Detailed, ERC20Capped, ERC20Pausable {
    constructor(string _detail, string _ticker, uint8 _decimels)
    ERC20Detailed(_detail, _ticker, _decimels)
    ERC20Capped(21000000) // 21mil
    public
    {
    
    }
}
