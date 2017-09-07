pragma solidity ^0.4.11;
import './Owned.sol';
import './Token.sol';
import './SafeMath.sol';

contract ApprovalReceiver {
    function receiveApproval(address _from, uint256 _value, address _tokenContract, bytes _extraData);
}


contract Rollback is Owned, ApprovalReceiver {

    event onSetCredit(address account , uint256 amount);
    event onReturned(address who, uint256 tokenAmount, uint256 ethAmount);


    using SafeMath for uint256;
    
    Token public token = Token(0xD850942eF8811f2A866692A623011bDE52a462C1);

    uint256 public totalSetCredit;                  //set ven that should be returned
    uint256 public totalReturnedCredit;             //returned ven  

    struct Credit {
        uint128 total;
        uint128 used;
    }

    mapping(address => Credit)  credits;           //public

    function Rollback() {
    }

    function() payable {
    }

    function withdrawETH(address _address,uint256 _amount) onlyOwner {
        require(_address != 0);
        _address.transfer(_amount);
    }

    function withdrawToken(address _address, uint256 _amount) onlyOwner {
        require(_address != 0);
        token.transfer(_address, _amount);
    }

    function setCredit(address _account, uint256 _amount) onlyOwner { 

        totalSetCredit += _amount;
        totalSetCredit -= credits[_account].total;        

        credits[_account].total = _amount.toUINT128();
        require(credits[_account].total >= credits[_account].used);
        onSetCredit(_account, _amount);
    }

    function getCredit(address _account) constant returns (uint256 total, uint256 used) {
        return (credits[_account].total, credits[_account].used);
    }    

    function receiveApproval(address _from, uint256 _value, address /*_tokenContract*/, bytes /*_extraData*/) {
        require(msg.sender == address(token));

        require(credits[_from].total >= credits[_from].used);
        uint256 remainedCredit = credits[_from].total - credits[_from].used;

        if(_value > remainedCredit)
            _value = remainedCredit;  

        uint256 balance = token.balanceOf(_from);
        if(_value > balance)
            _value = balance;

        require(_value > 0);

        require(token.transferFrom(_from, this, _value));

        uint256 ethAmount = _value / 4025;
        require(ethAmount > 0);

        credits[_from].used += _value.toUINT128();
        totalReturnedCredit +=_value;

        _from.transfer(ethAmount);
        
        onReturned(_from, _value, ethAmount);
    }
}