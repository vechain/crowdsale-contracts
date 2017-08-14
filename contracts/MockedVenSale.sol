pragma solidity ^0.4.11;
import './VenSale.sol';

contract MockedVENSale is VENSale {
    uint32 mockedBlockTime;

    function blockTime() constant returns (uint32) {
        return mockedBlockTime;
    }

    function setMockedBlockTime(uint32 _time) {
        mockedBlockTime = _time;
    }
}