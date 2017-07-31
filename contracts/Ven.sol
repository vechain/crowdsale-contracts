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

    struct Account {
        uint256 balance;
        // raw token can be transformed into balance with bonus
        uint256 rawTokens;
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
    function isSealed() internal constant returns (bool) {
        return owner == 0;
    }

    // Claim bonus by raw tokens
    function claimBonus(address _owner) internal{      
        require(isSealed());
        if (accounts[_owner].rawTokens != 0) {
            accounts[_owner].balance = balanceOf(_owner);
            accounts[_owner].rawTokens = 0;
        }
    }

    // What is the balance of a particular account?
    function balanceOf(address _owner) constant returns (uint256 balance) {
        if (accounts[_owner].rawTokens == 0)
            return accounts[_owner].balance;

        if (isSealed()) {
            uint256 bonus = 
                 accounts[_owner].rawTokens
                .mul(bonusOffered)
                .div(rawTokensSupplied.get());

            return accounts[_owner].balance = 
                 accounts[_owner].balance
                .add(accounts[_owner].rawTokens)
                .add(bonus);
        }
        
        return accounts[_owner].balance.add(accounts[_owner].rawTokens);
    }

    // Transfer the balance from owner's account to another account
    function transfer(address _to, uint256 _amount) returns (bool success) {
        require(isSealed());

        // implicitly claim bonus for both sender and receiver
        claimBonus(msg.sender);
        claimBonus(_to);

        if (accounts[msg.sender].balance >= _amount
            && _amount > 0
            && accounts[_to].balance + _amount > accounts[_to].balance) {
            accounts[msg.sender].balance -= _amount;
            accounts[_to].balance += _amount;
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

        if (accounts[_from].balance >= _amount
            && allowed[_from][msg.sender] >= _amount
            && _amount > 0
            && accounts[_to].balance + _amount > accounts[_to].balance) {
            accounts[_from].balance -= _amount;
            allowed[_from][msg.sender] -= _amount;
            accounts[_to].balance += _amount;
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

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    // Mint tokens and assign to some one
    function mint(address _owner, uint256 _amount, bool _isRaw) onlyOwner{
        if (_isRaw) {
            accounts[_owner].rawTokens = accounts[_owner].rawTokens.add(_amount);
            rawTokensSupplied.set(rawTokensSupplied.get().add(_amount));
        } else {
            accounts[_owner].balance = accounts[_owner].balance.add(_amount);
        }

        totalSupply = totalSupply.add(_amount);
        Transfer(0, _owner, _amount);
    }
    
    // Offer bonus to raw tokens holder
    function offerBonus(uint256 _bonus) onlyOwner {
        bonusOffered = bonusOffered.add(_bonus);
    }

    // Set owner to zero address, to disable mint, and enable token transfer
    function seal() onlyOwner {
        setOwner(0);

        totalSupply = totalSupply.add(bonusOffered);
        Transfer(0, address(-1), bonusOffered);
    }
}
