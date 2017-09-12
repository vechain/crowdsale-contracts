pragma solidity ^0.4.11;
import './Owned.sol';
import './Token.sol';
import './SafeMath.sol';


contract Exchange is Owned {

    event onExchangeTokenToEther(address who, uint256 tokenAmount, uint256 etherAmount);

    using SafeMath for uint256;

    Token public token = Token(0xD850942eF8811f2A866692A623011bDE52a462C1);

    // 1 ether = ? tokens
    uint256 public rate = 4025;

    // quota of token for every account that can be exchanged to ether
    uint256 public tokenQuota = 402500 ether;

    // quota of ether for every account that can be exchanged to token
    // uint256 public etherQuota = 100 ether;

    bool public tokenToEtherAllowed = true;
    // bool public etherToTokenAllowed = false;

    // uint256 public totalReturnedCredit;             //returned ven  


    // struct QuotaUsed {
    //     uint128 tokens;
    //     uint128 ethers;
    // }
    mapping(address => uint256) accountQuotaUsed;

    function Exchange() {
    }

    function () payable {
    }


    function withdrawEther(address _address,uint256 _amount) onlyOwner {
        require(_address != 0);
        _address.transfer(_amount);
    }

    function withdrawToken(address _address, uint256 _amount) onlyOwner {
        require(_address != 0);
        token.transfer(_address, _amount);
    }

    function quotaUsed(address _account) constant returns(uint256 ) {
        return accountQuotaUsed[_account];
    }

    //tested
    function setRate(uint256 _rate) onlyOwner {
        rate = _rate;
    }

    //tested
    function setTokenQuota(uint256 _quota) onlyOwner {
        tokenQuota = _quota;
    }

    // function setEtherQuota(uint256 _quota) onlyOwner {
    //     etherQuota = _quota;
    // }

    //tested    
    function setTokenToEtherAllowed(bool _allowed) onlyOwner {
        tokenToEtherAllowed = _allowed;
    }

    // function setEtherToTokenAllowed(bool _allowed) onlyOwner {
    //     etherToTokenAllowed = _allowed;
    // }

    function receiveApproval(address _from, uint256 _value, address /*_tokenContract*/, bytes /*_extraData*/) {
        exchangeTokenToEther(_from, _value);
    }

    function exchangeTokenToEther(address _from, uint256 _tokenAmount) internal {
        require(tokenToEtherAllowed);
        require(msg.sender == address(token));
        require(!isContract(_from));

        uint256 quota = tokenQuota.sub(accountQuotaUsed[_from]);                

        if (_tokenAmount > quota)
            _tokenAmount = quota;
        
        uint256 balance = token.balanceOf(_from);
        if (_tokenAmount > balance)
            _tokenAmount = balance;

        require(_tokenAmount>0);    //require the token should be above 0

        //require(_tokenAmount > 0.01 ether);
        require(token.transferFrom(_from, this, _tokenAmount));        

        accountQuotaUsed[_from] = _tokenAmount.add(accountQuotaUsed[_from]);
        
        uint256 etherAmount = _tokenAmount / rate;
        require(etherAmount > 0);
        _from.transfer(etherAmount);

        // totalReturnedCredit+=_tokenAmount;

        onExchangeTokenToEther(_from, _tokenAmount, etherAmount);
    }


    //exchange EtherToToken放到fallback函数中
    //TokenToEther
    //    function exchangeEtherToToken() payable {
    //       require(etherToTokenAllowed);
    //        require(!isContract(msg.sender));
    //
    //        uint256 quota = etherQuota.sub(accountQuotaUsed[msg.sender].ethers);

    //        uint256 etherAmount = msg.value;
    //        require(etherAmount >= 0.01 ether && etherAmount <= quota);
    //        
    //        uint256 tokenAmount = etherAmount * rate;

    //        accountQuotaUsed[msg.sender].ethers = etherAmount.add(accountQuotaUsed[msg.sender].ethers).toUINT128();

    //        require(token.transfer(msg.sender, tokenAmount));

    //        onExchangeEtherToToken(msg.sender, tokenAmount, etherAmount);                                                        
    //    }

    function isContract(address _addr) constant internal returns(bool) {
        uint size;
        if (_addr == 0)
            return false;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }
}

