pragma solidity ^0.4.11;
import './VenSale.sol';

contract MockedVENSale is VENSale {
    uint mockedBlockTime;

    function blockTime() constant returns (uint) {
        return mockedBlockTime;
    }

    function setMockedBlockTime(uint _time) {
        mockedBlockTime = _time;
    }
}