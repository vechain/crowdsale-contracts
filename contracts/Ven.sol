pragma solidity ^0.4.11;

import "./Token.sol";
import "./Owned.sol";
import "./SafeMath.sol";
import "./Prealloc.sol";

/// VEN token, ERC20 compliant
contract VEN is Token, Owned {
    using SafeMath for uint256;

    string public constant name    = "VeChain Token";  //The Token's name
    uint8 public constant decimals = 18;               //Number of decimals of the smallest unit
    string public constant symbol  = "VEN";            //An identifier    

    // Algined to 256bit to save gas usage.
    // uint112's max value is about 5e33.
    // it's enough to present amount of tokens
    struct Account {
        uint112 balance;
        // raw token can be transformed into balance with bonus
        uint112 rawTokens;
        // safe to store timestamp
        uint32 lastMintedTimestamp;
    }

    // Balances for each account
    mapping(address => Account) accounts;

    // Owner of account approves the transfer of an amount to another account
    mapping(address => mapping(address => uint256)) allowed;

    // every buying will update this var. 
    // pre-alloc to make first buying cost no much more gas than subsequent
    using Prealloc for Prealloc.UINT256;
    Prealloc.UINT256 rawTokensSupplied;

    // bonus that can be shared by raw tokens
    uint256 bonusOffered;

    // Constructor
    function VEN() {
        rawTokensSupplied.set(0);
    }

    // Send back ether sent to me
    function () {
        revert();
    }

    // If sealed, transfer is enabled and mint is disabled
    function isSealed() constant returns (bool) {
        return owner == 0;
    }

    function lastMintedTimestamp(address _owner) constant returns(uint32) {
        return accounts[_owner].lastMintedTimestamp;
    }

    // Claim bonus by raw tokens
    function claimBonus(address _owner) internal{      
        require(isSealed());
        if (accounts[_owner].rawTokens != 0) {
            uint256 realBalance = balanceOf(_owner);
            uint256 bonus = realBalance
                .sub(accounts[_owner].balance)
                .sub(accounts[_owner].rawTokens);

            accounts[_owner].balance = realBalance.toUINT112();
            accounts[_owner].rawTokens = 0;
            if(bonus > 0){
                Transfer(this, _owner, bonus);
            }
        }
    }

    // What is the balance of a particular account?
    function balanceOf(address _owner) constant returns (uint256 balance) {
        if (accounts[_owner].rawTokens == 0)
            return accounts[_owner].balance;

        if (bonusOffered > 0) {
            uint256 bonus = bonusOffered
                 .mul(accounts[_owner].rawTokens)
                 .div(rawTokensSupplied.get());

            return bonus.add(accounts[_owner].balance)
                    .add(accounts[_owner].rawTokens);
        }
        
        return accounts[_owner].balance + accounts[_owner].rawTokens;
    }

    // Transfer the balance from owner's account to another account
    function transfer(address _to, uint256 _amount) returns (bool success) {
        require(isSealed());

        // implicitly claim bonus for both sender and receiver
        claimBonus(msg.sender);
        claimBonus(_to);

        // according to VEN's total supply, never overflow here
        if (accounts[msg.sender].balance >= _amount
            && _amount > 0) {            
            accounts[msg.sender].balance -= uint112(_amount);
            accounts[_to].balance += uint112(_amount);
            Transfer(msg.sender, _to, _amount);
            return true;
        } else {
            return false;
        }
    }

    // Send _value amount of tokens from address _from to address _to
    // The transferFrom method is used for a withdraw workflow, allowing contracts to send
    // tokens on your behalf, for example to "deposit" to a contract address and/or to charge
    // fees in sub-currencies; the command should fail unless the _from account has
    // deliberately authorized the sender of the message via some mechanism; we propose
    // these standardized APIs for approval:
    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) returns (bool success) {
        require(isSealed());

        // implicitly claim bonus for both sender and receiver
        claimBonus(_from);
        claimBonus(_to);

        // according to VEN's total supply, never overflow here
        if (accounts[_from].balance >= _amount
            && allowed[_from][msg.sender] >= _amount
            && _amount > 0) {
            accounts[_from].balance -= uint112(_amount);
            allowed[_from][msg.sender] -= _amount;
            accounts[_to].balance += uint112(_amount);
            Transfer(_from, _to, _amount);
            return true;
        } else {
            return false;
        }
    }

    // Allow _spender to withdraw from your account, multiple times, up to the _value amount.
    // If this function is called again it overwrites the current allowance with _value.
    function approve(address _spender, uint256 _amount) returns (bool success) {
        allowed[msg.sender][_spender] = _amount;
        Approval(msg.sender, _spender, _amount);
        return true;
    }

    /* Approves and then calls the receiving contract */
    function approveAndCall(address _spender, uint256 _value, bytes _extraData) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);

        //call the receiveApproval function on the contract you want to be notified. This crafts the function signature manually so one doesn't have to include a contract in here just for this.
        //receiveApproval(address _from, uint256 _value, address _tokenContract, bytes _extraData)
        //it is assumed that when does this that the call *should* succeed, otherwise one would use vanilla approve instead.
        //if(!_spender.call(bytes4(bytes32(sha3("receiveApproval(address,uint256,address,bytes)"))), msg.sender, _value, this, _extraData)) { revert(); }
        ApprovalReceiver(_spender).receiveApproval(msg.sender, _value, this, _extraData);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    // Mint tokens and assign to some one
    function mint(address _owner, uint256 _amount, bool _isRaw, uint32 timestamp) onlyOwner{
        if (_isRaw) {
            accounts[_owner].rawTokens = _amount.add(accounts[_owner].rawTokens).toUINT112();
            rawTokensSupplied.set(rawTokensSupplied.get().add(_amount));
        } else {
            accounts[_owner].balance = _amount.add(accounts[_owner].balance).toUINT112();
        }

        accounts[_owner].lastMintedTimestamp = timestamp;

        totalSupply = totalSupply.add(_amount);
        Transfer(0, _owner, _amount);
    }
    
    // Offer bonus to raw tokens holder
    function offerBonus(uint256 _bonus) onlyOwner { 
        bonusOffered = bonusOffered.add(_bonus);
        totalSupply = totalSupply.add(_bonus);
        Transfer(0, this, _bonus);
    }

    // Set owner to zero address, to disable mint, and enable token transfer
    function seal() onlyOwner {
        setOwner(0);
    }
}

contract ApprovalReceiver {
    function receiveApproval(address _from, uint256 _value, address _tokenContract, bytes _extraData);
}
