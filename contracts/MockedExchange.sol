pragma solidity ^0.4.11;

import './Exchange.sol';
import './Token.sol';

contract MockedExchange is Exchange {
    function setToken(Token _token) {
        token = _token;
    }
}