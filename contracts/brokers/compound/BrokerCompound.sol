// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../../interfaces/AbstractBroker.sol";
import "../../interfaces/IOnchainVaults.sol";
import "../../interfaces/IOrderRegistry.sol";
import "./interfaces/ICErc20.sol";

/**
 * @title Compound broker
 */
contract BrokerCompound is AbstractBroker {
    using Address for address;
    using SafeERC20 for IERC20;

    // The address of Compound interest-bearing token (e.g. cDAI, cUSDT)
    address public immutable cErc20;
    
    uint256 nonce;
    uint256 constant EXP_TIME = 2e7; // expiration time stamp of the limit order 

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply,
        address _exchange,
        address _orderRegistry,
        address _onchainVaults,
        address _cErc20
    ) AbstractBroker(_name, _symbol, _decimals, _initialSupply, _exchange, _orderRegistry, _onchainVaults) {
        cErc20 = _cErc20;
    }

    /**
     * @notice 
     */
    function mintAndSell(uint256 _rideId, uint256 _amount, uint256 _tokenIdFee, uint256 _amountFee, uint256 _vaultIdFee) override external onlyOwner {

        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId];
        require(rideAssetsInfo.tokenIdShare != 0, "ride assets info not registered");

        _mint(msg.sender, _amount);

        IERC20(this).safeIncreaseAllowance(onchainVaults, _amount);
        IOnchainVaults(onchainVaults).depositERC20ToVault(rideAssetsInfo.tokenIdShare, rideAssetsInfo.vaultIdShare, _amount / rideAssetsInfo.quantumShare);

        nonce += 1;
        IOrderRegistry(orderRegistry).registerLimitOrder(exchange, rideAssetsInfo.tokenIdShare, rideAssetsInfo.tokenIdInput, _tokenIdFee, 
            _amount / rideAssetsInfo.quantumShare, _amount / rideAssetsInfo.quantumInput, _amountFee, 
            rideAssetsInfo.vaultIdShare, rideAssetsInfo.vaultIdInput, _vaultIdFee, nonce, EXP_TIME);
        ridesShares[_rideId] = _amount;
    }

    /**
     * @notice 
     */
    function cancelSell(uint256 _rideId, uint256 _amount) override external onlyOwner {

    }

    /**
     * @notice 
     */
    function departRide(uint256 _rideId, uint256 _tokenIdFee, uint256 _amountFee, uint256 _vaultIdFee) override external onlyOwner {
        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId];
        require(rideAssetsInfo.tokenIdShare != 0, "ride assets info not registered");

        uint256 amount = ridesShares[_rideId];
        require(amount > 0, "ride does not sell any shares yet");

        IOnchainVaults(onchainVaults).withdrawFromVault(rideAssetsInfo.tokenIdInput, rideAssetsInfo.vaultIdInput, amount / rideAssetsInfo.quantumInput);

        IERC20(this).safeIncreaseAllowance(cErc20, amount);
        uint256 ctokenAmt = ICErc20(cErc20).mint(amount);
        uint256 expectMinResult = amount * prices[_rideId] * (SLIPPAGE_DENOMINATOR - slippages[_rideId]) / PRICE_DECIMALS / SLIPPAGE_DENOMINATOR;

        require(ctokenAmt > expectMinResult, "price and slippage not fulfilled");
        ridesShares[_rideId] = 0;

        ICErc20(cErc20).approve(onchainVaults, ctokenAmt);
        IOnchainVaults(onchainVaults).depositERC20ToVault(rideAssetsInfo.tokenIdOutput, rideAssetsInfo.vaultIdOutput, ctokenAmt / rideAssetsInfo.quantumOutput);

        nonce += 1;
        IOrderRegistry(orderRegistry).registerLimitOrder(exchange, rideAssetsInfo.tokenIdOutput, rideAssetsInfo.tokenIdShare, _tokenIdFee, 
            ctokenAmt / rideAssetsInfo.quantumOutput, amount / rideAssetsInfo.quantumShare, _amountFee, 
            rideAssetsInfo.vaultIdOutput, rideAssetsInfo.vaultIdShare, _vaultIdFee, nonce, EXP_TIME);
    }

    /**
     * @notice 
     */
    function burnRideShares(uint256 _rideId) override external onlyOwner {

    }

    /**
     * @notice 
     */
    function redeemShare(uint256 _amount) override external onlyOwner {
        
    }
}
