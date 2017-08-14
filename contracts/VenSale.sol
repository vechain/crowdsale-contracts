pragma solidity ^0.4.11;

import "./Owned.sol";
import "./Ven.sol";
import "./SafeMath.sol";
import "./Prealloc.sol";

// Contract to sell and distribute VEN tokens
contract VENSale is Owned{

    /// chart of stage transition 
    ///
    /// deploy   initialize      startTime                            endTime                 finalize
    ///                              | <-earlyStageLasts-> |             | <- closedStageLasts -> |
    ///  O-----------O---------------O---------------------O-------------O------------------------O------------>
    ///     Created     Initialized           Early             Normal             Closed            Finalized
    enum Stage {
        NotCreated,
        Created,
        Initialized,
        Early,
        Normal,
        Closed,
        Finalized
    }

    using SafeMath for uint256;
    
    uint256 public constant totalSupply         = (10 ** 9) * (10 ** 18); // 1 billion VEN, decimals set to 18

    uint256 constant privateSupply              = totalSupply * 9 / 100;  // 9% for private ICO
    uint256 constant commercialPlan             = totalSupply * 23 / 100; // 23% for commercial plan
    uint256 constant reservedForTeam            = totalSupply * 5 / 100;  // 5% for team
    uint256 constant reservedForOperations      = totalSupply * 22 / 100; // 22 for operations

    // 59%
    uint256 public constant nonPublicSupply     = privateSupply + commercialPlan + reservedForTeam + reservedForOperations;
    // 41%
    uint256 public constant publicSupply = totalSupply - nonPublicSupply;


    uint256 public constant officialLimit = 64371825 * (10 ** 18);
    uint256 public constant channelsLimit = publicSupply - officialLimit;

    using Prealloc for Prealloc.UINT256;
    Prealloc.UINT256 officialSold_; // amount of tokens officially sold out

    uint256 public channelsSold;    // amount of tokens sold out via channels
    
    uint256 constant venPerEth = 3500;  // normal exchange rate
    uint256 constant venPerEthEarlyStage = venPerEth + venPerEth * 15 / 100;  // early stage has 15% reward

    uint constant minBuyInterval = 30 minutes; // each account can buy once in 30 minutes
    uint constant maxBuyEthAmount = 30 ether;
   
    VEN ven; // VEN token contract follows ERC20 standard

    address ethVault; // the account to keep received ether
    address venVault; // the account to keep non-public offered VEN tokens

    uint public constant startTime = 1503057600; // time to start sale
    uint public constant endTime = 1504180800;   // tiem to close sale
    uint public constant earlyStageLasts = 3 days; // early bird stage lasts in seconds

    bool initialized;
    bool finalized;

    function VENSale() {
        officialSold_.set(0);
    }    

    /// @notice calculte exchange rate according to current stage
    /// @return exchange rate. zero if not in sale.
    function exchangeRate() constant returns (uint256){
        if (stage() == Stage.Early) {
            return venPerEthEarlyStage;
        }
        if (stage() == Stage.Normal) {
            return venPerEth;
        }
        return 0;
    }

    /// @notice for test purpose
    function blockTime() constant returns (uint32) {
        return uint32(block.timestamp);
    }

    /// @notice estimate stage
    /// @return current stage
    function stage() constant returns (Stage) { 
        if (finalized) {
            return Stage.Finalized;
        }

        if (!initialized) {
            // deployed but not initialized
            return Stage.Created;
        }

        if (blockTime() < startTime) {
            // not started yet
            return Stage.Initialized;
        }

        if (officialSold_.get().add(channelsSold) >= publicSupply) {
            // all sold out
            return Stage.Closed;
        }

        if (blockTime() < endTime) {
            // in sale            
            if (blockTime() < startTime.add(earlyStageLasts)) {
                // early bird stage
                return Stage.Early;
            }
            // normal stage
            return Stage.Normal;
        }

        // closed
        return Stage.Closed;
    }

    function isContract(address _addr) constant internal returns(bool) {
        uint size;
        if (_addr == 0) return false;
        assembly {
            size := extcodesize(_addr)
        }
        return size > 0;
    }

    /// @notice entry to buy tokens
    function () payable {        
        buy();
    }

    /// @notice entry to buy tokens
    function buy() payable {
        // reject contract buyer to avoid breaking interval limit
        require(!isContract(msg.sender));
        require(msg.value >= 0.01 ether);

        uint256 rate = exchangeRate();
        // here don't need to check stage. rate is only valid when in sale
        require(rate > 0);
        // each account is allowed once in minBuyInterval
        require(blockTime() >= ven.lastMintedTimestamp(msg.sender) + minBuyInterval);

        uint256 requested;
        // and limited to maxBuyEthAmount
        if (msg.value > maxBuyEthAmount) {
            requested = maxBuyEthAmount.mul(rate);
        } else {
            requested = msg.value.mul(rate);
        }

        uint256 remained = officialLimit.sub(officialSold_.get());
        if (requested > remained) {
            //exceed remained
            requested = remained;
        }

        uint256 ethCost = requested.div(rate);
        if (requested > 0) {
            ven.mint(msg.sender, requested, true, blockTime());
            // transfer ETH to vault
            ethVault.transfer(ethCost);

            officialSold_.set(officialSold_.get().add(requested));
            onSold(msg.sender, requested, ethCost);        
        }

        uint256 toReturn = msg.value.sub(ethCost);
        if(toReturn > 0) {
            // return over payed ETH
            msg.sender.transfer(toReturn);
        }        
    }

    /// @notice calculate tokens sold officially
    function officialSold() constant returns (uint256) {
        return officialSold_.get();
    }

    /// @notice manually offer tokens to channel
    function offerToChannel(address _channelAccount, uint256 _venAmount) onlyOwner {
        Stage stg = stage();
        // since the settlement may be delayed, so it's allowed in closed stage
        require(stg == Stage.Early || stg == Stage.Normal || stg == Stage.Closed);

        channelsSold = channelsSold.add(_venAmount);

        //should not exceed limit
        require(channelsSold <= channelsLimit);

        ven.mint(
            _channelAccount,
            _venAmount,
            true,  // unsold tokens can be claimed by channels portion
            blockTime()
            );

        onSold(_channelAccount, _venAmount, 0);
    }

    /// @notice initialize to prepare for sale
    /// @param _ven The address VEN token contract following ERC20 standard
    /// @param _ethVault The place to store received ETH
    /// @param _venVault The place to store non-publicly supplied VEN tokens
    function initialize(
        VEN _ven,
        address _ethVault,
        address _venVault) onlyOwner {
        require(stage() == Stage.Created);

        // ownership of token contract should already be this
        require(_ven.owner() == address(this));

        require(address(_ethVault) != 0);
        require(address(_venVault) != 0);      

        ven = _ven;
        
        ethVault = _ethVault;
        venVault = _venVault;    
        
        ven.mint(
            venVault,
            reservedForTeam.add(reservedForOperations),
            false, // team and operations reserved portion can't share unsold tokens
            blockTime()
        );

        ven.mint(
            venVault,
            privateSupply.add(commercialPlan),
            true, // private ICO and commercial plan can share unsold tokens
            blockTime()
        );

        initialized = true;
        onInitialized();
    }

    /// @notice finalize
    function finalize() onlyOwner {
        // only after closed stage
        require(stage() == Stage.Closed);       

        uint256 unsold = publicSupply.sub(officialSold_.get()).sub(channelsSold);

        if (unsold > 0) {
            // unsold VEN as bonus
            ven.offerBonus(unsold);        
        }
        ven.seal();

        finalized = true;
        onFinalized();
    }

    event onInitialized();
    event onFinalized();

    event onSold(address indexed buyer, uint256 venAmount, uint256 ethCost);
}
