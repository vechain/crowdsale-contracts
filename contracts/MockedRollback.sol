pragma solidity ^0.4.11;

import './Rollback.sol';
import './Token.sol';

contract MockedRollback is Rollback {

    function setToken(Token _token) {
        token = _token;
    }
}