// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/ICErc20.sol";
import "./interfaces/ICEth.sol";
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

    function sellErc(address inputToken, address outputToken, uint256 inputAmt) external onlyBroker returns (uint256 outputAmt) {
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), inputAmt);
        uint256 amtBeforeSell = ICErc20(outputToken).balanceOf(address(this));
        uint256 mintResult = ICErc20(outputToken).mint(inputAmt);
        require(mintResult == 0, "Couldn't mint cToken");
        uint256 amtAfterSell = ICErc20(outputToken).balanceOf(address(this));
        outputAmt = amtAfterSell - amtBeforeSell;
        IERC20(outputToken).safeTransfer(msg.sender, outputAmt);
    }

    function sellEth(address outputToken) external onlyBroker payable returns (uint256 outputAmt) {
        uint256 amtBeforeSell = ICEth(outputToken).balanceOf(address(this));
        ICEth(outputToken).mint{value: msg.value}();
        uint256 amtAfterSell = ICEth(outputToken).balanceOf(address(this));
        outputAmt = amtAfterSell - amtBeforeSell;
        IERC20(outputToken).safeTransfer(msg.sender, outputAmt);
    }

    function updateBroker(address _broker) external onlyOwner {
        broker = _broker;
        emit BrokerUpdated(broker);
    }
}
