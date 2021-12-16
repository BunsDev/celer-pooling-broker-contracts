// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ICErc20.sol";
import "../../interfaces/IStrategyPool.sol";

/**
 * @title Compound pool
 */
contract StrategyCompound is IStrategyPool, Ownable {
    using SafeERC20 for IERC20;

    address public broker;
    modifier onlyBroker() {
        require(msg.sender == broker, "caller is not broker");
        _;
    }

    event BrokerUpdated(address broker);

    constructor(
        address _broker
    ) {
        broker = _broker;
    }

    function sell(address inputToken, address outputToken, uint256 inputAmt) external onlyBroker returns (uint256 outputAmt) {
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), inputAmt);
        outputAmt = ICErc20(outputToken).mint(inputAmt);
        IERC20(outputToken).safeTransfer(msg.sender, outputAmt);
    }

    function updateBroker(address _broker) external onlyOwner {
        broker = _broker;
        emit BrokerUpdated(broker);
    }
}
