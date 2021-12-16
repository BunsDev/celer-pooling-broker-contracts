// SPDX-License-Identifier: GPL-3.0-only

pragma solidity 0.8.9;

interface IStrategyPool {
    // sell the amount of the input token, and the amount of output token will be sent to msg.sender
    function sell(address inputToken, address outputToken, uint256 inputAmt) external returns (uint256 outputAmt);
}
