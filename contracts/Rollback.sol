pragma solidity ^0.4.11;
import './Owned.sol';
import './Token.sol';

contract Rollback is Owned{

    event onSetCredit(address account , uint256 amount);
    event onReturned(address who, uint256 venAmount, uint256 ethAmount);

    Token constant ven = Token(0xD850942eF8811f2A866692A623011bDE52a462C1);
    uint256 public totalCredit;
    mapping(address => uint256) credits;
    address venVault;

    function Rollback() {
    }

    function setVENVault(address _venVault) onlyOwner {
        venVault = _venVault;
    }

    function setCredit(address _account, uint256 _amount) onlyOwner { 
        totalCredit += _amount;
        totalCredit -= credits[_account];        

        credits[_account] = _amount;       
        onSetCredit(_account, _amount);
    }
    
    function() payable {
    }

    function receiveApproval(address _from, uint256 _value, address _tokenContract, bytes _extraData) {
        require(venVault != 0);
        require(msg.sender == address(ven));
        
        if(_value > credits[_from])
            _value = credits[_from];
        require(_value > 0);

        require(ven.transferFrom(_from, venVault, _value));

        uint256 ethAmount = _value / 4025;
        require(ethAmount > 0);

        credits[_from] -= _value;
        _from.transfer(ethAmount);       

        onReturned(_from, _value, ethAmount);
    }
}