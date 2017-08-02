pragma solidity ^0.4.11;

import "./Owned.sol";
import "./Ven.sol";
import "./SafeMath.sol";

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

    uint256 public constant officialLimit       = totalSupply * 8 / 100;  // 8% for official public sale
    uint256 public constant channelsLimit       = totalSupply - nonPublicSupply - officialLimit; // 33% offered to channels
    
    uint256 constant venPerEth = 3500;  // normal exchange rate
    uint256 constant venPerEthEarlyStage = venPerEth + venPerEth * 15 / 100;  // early stage has 15% reward

    uint256 public channelsSold; // amount of tokens sold out via channels
   
    VEN ven; // VEN token contract follows ERC20 standard

    address ethVault; // the account to keep received ether
    address venVault; // the account to keep non-public offered VEN tokens

    uint public startTime; // time to start sale
    uint public endTime;   // tiem to close sale
    uint public earlyStageLasts; // early bird stage lasts in seconds

    bool initialized;
    bool finalized;

    function VENSale() {
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
    function blockTime() constant returns (uint) {
        return block.timestamp;
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

        if (ven.totalSupply() >= totalSupply) {
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

    /// @notice entry to buy tokens
    function () payable {        
        buy();
    }

    /// @notice entry to buy tokens
    function buy() payable {
        require(msg.value >= 0.01 ether);

        uint256 rate = exchangeRate();
        // here don't need to check stage. rate is only valid when in sale
        require(rate > 0);

        uint256 remained = officialLimit.sub(officialSold());
        uint256 requested = msg.value.mul(rate);

        if (requested > remained) {
            //exceed remained
            requested = remained;
        }

        ven.mint(msg.sender, requested, true);

        uint256 ethCost = requested.div(rate);
        // transfer ETH to vault
        ethVault.transfer(ethCost);

        uint256 toReturn = msg.value.sub(ethCost);
        if(toReturn > 0) {
            // return over payed ETH
            msg.sender.transfer(toReturn);
        }
        onSold(msg.sender, requested, ethCost);
    }

    /// @notice calculate tokens sold officially
    function officialSold() constant returns (uint256) {
        return ven.totalSupply().sub(nonPublicSupply).sub(channelsSold);
    }

    /// @notice manually offer tokens to channels
    function offerToChannels(uint256 _venAmount) onlyOwner {
        Stage stg = stage();
        // since the settlement may be delayed, so it's allowed in closed stage
        require(stg == Stage.Early || stg == Stage.Normal || stg == Stage.Closed);

        channelsSold = channelsSold.add(_venAmount);

        //should not exceed limit
        require(channelsSold <= channelsLimit);

        ven.mint(
            venVault,
            _venAmount,
            true  // unsold tokens can be claimed by channels portion
            );

        onSold(venVault, _venAmount, 0);
    }

    /// @notice initialize to prepare for sale
    /// @param _ven The address VEN token contract following ERC20 standard
    /// @param _ethVault The place to store received ETH
    /// @param _venVault The place to store non-publicly supplied VEN tokens
    /// @param _startTime The time when sale starts
    /// @param _endTime The time when sale ends
    /// @param _earlyStageLasts duration of early stage
    function initialize(
        VEN _ven,
        address _ethVault,
        address _venVault,
        uint _startTime,
        uint _endTime,
        uint _earlyStageLasts) onlyOwner {
        require(stage() == Stage.Created);

        // ownership of token contract should already be this
        require(_ven.owner() == address(this));

        require(address(_ethVault) != 0);
        require(address(_venVault) != 0);

        require(_startTime > blockTime());
        require(_startTime.add(_earlyStageLasts) < _endTime);        

        ven = _ven;
        ethVault = _ethVault;
        venVault = _venVault;

        startTime = _startTime;
        endTime = _endTime;
        earlyStageLasts = _earlyStageLasts;

        initialized = true;
        
        ven.mint(
            venVault,
            nonPublicSupply.sub(privateSupply).sub(commercialPlan),
            false // team and operations reserved portion can't share unsold tokens
        );

        ven.mint(
            venVault,
            privateSupply.add(commercialPlan),
            true // private ICO and commercial plan can share unsold tokens
        );
        onInitialized();
    }

    /// @notice finalize
    function finalize() onlyOwner {
        // only after closed stage
        require(stage() == Stage.Closed);       

        uint256 unsold = totalSupply.sub(ven.totalSupply());

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
