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
 * share : inputtoken = 1 : 1, outputtoken : share = price
 */
contract BrokerCompound is AbstractBroker {
    using Address for address;
    using SafeERC20 for IERC20;

    // The address of Compound interest-bearing token (e.g. cDAI, cUSDT)
    address public immutable cErc20;
    address public immutable supplyToken;
    
    uint256 nonce;
    uint256 constant EXP_TIME = 2e7; // expiration time stamp of the limit order 

    mapping (uint256=>uint256) actualPrices; //rideid=>actual price

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _onchainVaults,
        address _cErc20,
        address _supplytoken
    ) AbstractBroker(_name, _symbol, _decimals, _onchainVaults) {
        cErc20 = _cErc20;
        supplyToken = _supplytoken;
    }

    /**
     * @notice 
     */
    function mintShareAndSell(uint256 _rideId, uint256 _amount, uint256 _tokenIdFee, uint256 _amountFee, uint256 _vaultIdFee) override external onlyOwner {

        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId];
        require(rideAssetsInfo.tokenIdShare != 0, "ride assets info not registered");
        require(ridesShares[_rideId] == 0, "already mint for this ride"); //not mint yet for this ride

        _mint(address(this), _amount);

        IERC20(this).safeIncreaseAllowance(onchainVaults, _amount);
        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        uint256 quantumShare = ocv.getQuantum(rideAssetsInfo.tokenIdShare);
        uint256 quantumInput = ocv.getQuantum(rideAssetsInfo.tokenIdInput);
        ocv.depositERC20ToVault(rideAssetsInfo.tokenIdShare, rideAssetsInfo.vaultIdShare, _amount / quantumShare);

        nonce += 1;
        IOrderRegistry(ocv.orderRegistryAddress()).registerLimitOrder(onchainVaults, rideAssetsInfo.tokenIdShare, rideAssetsInfo.tokenIdInput, _tokenIdFee, 
            _amount / quantumShare, _amount / quantumInput, _amountFee, 
            rideAssetsInfo.vaultIdShare, rideAssetsInfo.vaultIdInput, _vaultIdFee, nonce, EXP_TIME);
        ridesShares[_rideId] = _amount;

        emit MintAndSell(_rideId, _amount);
    }

    /**
     * @notice 
     */
    function cancelSell(uint256 _rideId, uint256 _tokenIdFee, uint256 _amountFee, uint256 _vaultIdFee) override external onlyOwner {
        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId];
        require(rideAssetsInfo.tokenIdShare != 0, "ride assets info not registered");

        uint256 amount = ridesShares[_rideId];
        require(amount > 0, "ride does not sell any shares yet");

        bool departed = rideDeparted[_rideId];
        require(!departed, "ride departed already");

        nonce += 1;
        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        uint256 quantumShare = ocv.getQuantum(rideAssetsInfo.tokenIdShare);
        uint256 quantumInput = ocv.getQuantum(rideAssetsInfo.tokenIdInput);
        IOrderRegistry(ocv.orderRegistryAddress()).registerLimitOrder(onchainVaults, rideAssetsInfo.tokenIdInput, rideAssetsInfo.tokenIdShare, _tokenIdFee, 
            amount / quantumInput, amount / quantumShare, _amountFee, 
            rideAssetsInfo.vaultIdInput, rideAssetsInfo.vaultIdShare, _vaultIdFee, nonce, EXP_TIME);

        emit CancelSell(_rideId, amount);
    }

    /**
     * @notice 
     * share : inputtoken = 1 : 1, outputtoken : share = price
     */
    function departRide(uint256 _rideId, uint256 _tokenIdFee, uint256 _amountFee, uint256 _vaultIdFee) override external onlyOwner {
        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId];
        require(rideAssetsInfo.tokenIdShare != 0, "ride assets info not registered");

        bool departed = rideDeparted[_rideId];
        require(!departed, "ride departed already");

        rideDeparted[_rideId] = true;

        burnRideShares(_rideId); //burn unsold shares
        uint256 amount = ridesShares[_rideId]; //get the left amount
        require(amount > 0, "ride does not sell any shares yet");

        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        uint256 inputTokenVaultBalance = ocv.getVaultBalance(address(this), rideAssetsInfo.tokenIdInput, rideAssetsInfo.vaultIdInput);
        ocv.withdrawFromVault(rideAssetsInfo.tokenIdInput, rideAssetsInfo.vaultIdInput, inputTokenVaultBalance);

        uint256 quantumShare = ocv.getQuantum(rideAssetsInfo.tokenIdShare);
        uint256 quantumInput = ocv.getQuantum(rideAssetsInfo.tokenIdInput);
        uint256 quantumOutput = ocv.getQuantum(rideAssetsInfo.tokenIdOutput);

        uint256 inputTokenAmt = inputTokenVaultBalance * quantumInput;
        IERC20(supplyToken).safeIncreaseAllowance(cErc20, inputTokenAmt);
        uint256 ctokenAmt = ICErc20(cErc20).mint(inputTokenAmt);
        uint256 expectMinResult = amount * prices[_rideId] * (SLIPPAGE_DENOMINATOR - slippages[_rideId]) / PRICE_DECIMALS / SLIPPAGE_DENOMINATOR;

        require(ctokenAmt >= expectMinResult, "price and slippage not fulfilled");

        actualPrices[_rideId] = ctokenAmt * PRICE_DECIMALS / amount;

        ICErc20(cErc20).approve(onchainVaults, ctokenAmt);
        ocv.depositERC20ToVault(rideAssetsInfo.tokenIdOutput, rideAssetsInfo.vaultIdOutput, ctokenAmt / quantumOutput);

        nonce += 1;
        IOrderRegistry(ocv.orderRegistryAddress()).registerLimitOrder(onchainVaults, rideAssetsInfo.tokenIdOutput, rideAssetsInfo.tokenIdShare, _tokenIdFee, 
            ctokenAmt / quantumOutput, amount / quantumShare, _amountFee, 
            rideAssetsInfo.vaultIdOutput, rideAssetsInfo.vaultIdShare, _vaultIdFee, nonce, EXP_TIME);

        emit RideDeparted(_rideId, inputTokenAmt);
    }

    /**
     * @notice 
     */
    function burnRideShares(uint256 _rideId) override public onlyOwner {
        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId];
        require(rideAssetsInfo.tokenIdShare != 0, "ride assets info not registered");

        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        uint256 quantumShare = ocv.getQuantum(rideAssetsInfo.tokenIdShare);
        uint256 amount = ridesShares[_rideId];
        uint256 vaultBalance = ocv.getVaultBalance(address(this), rideAssetsInfo.tokenIdShare, rideAssetsInfo.vaultIdShare);
        uint256 amountToBurn = min(amount / quantumShare, vaultBalance);
        require(amountToBurn > 0, "no ride shares to burn");

        uint256 balanceBeforeWd = IERC20(this).balanceOf(address(this));
        ocv.withdrawFromVault(rideAssetsInfo.tokenIdShare, rideAssetsInfo.vaultIdShare, amountToBurn);
        uint256 balanceAfterWd = IERC20(this).balanceOf(address(this));

        uint256 wdAmt = balanceAfterWd - balanceBeforeWd;
        ridesShares[_rideId] = amount - wdAmt;
        _burn(address(this), wdAmt);

        emit SharesBurned(_rideId, wdAmt);
    }

    /**
     * @notice 
     * TODO: where to maintain the user list of a ride, in order to check if the caller is the ride user? 
     */
    function redeemShare(uint256 _rideId, uint256 _amount) override external {
        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId];
        require(rideAssetsInfo.tokenIdShare != 0, "ride assets info not registered");

        IERC20(this).safeTransferFrom(msg.sender, address(this), _amount);

        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        bool departed = rideDeparted[_rideId];
        if (departed) {
            //swap to output token
            uint256 boughtAmt = _amount * actualPrices[_rideId] / PRICE_DECIMALS;
            
            uint256 quantumOutput = ocv.getQuantum(rideAssetsInfo.tokenIdOutput);
            uint256 balanceBeforeWd = ICErc20(cErc20).balanceOf(address(this));
            ocv.withdrawFromVault(rideAssetsInfo.tokenIdOutput, rideAssetsInfo.vaultIdOutput, boughtAmt / quantumOutput);
            uint256 balanceAfterWd = ICErc20(cErc20).balanceOf(address(this));
            ICErc20(cErc20).transfer(msg.sender, balanceAfterWd - balanceBeforeWd);
        } else {
            //swap to input boken
            uint256 quantumInput = ocv.getQuantum(rideAssetsInfo.tokenIdInput);
            uint256 balanceBeforeWd = IERC20(supplyToken).balanceOf(address(this));
            ocv.withdrawFromVault(rideAssetsInfo.tokenIdInput, rideAssetsInfo.vaultIdInput, _amount / quantumInput);
            uint256 balanceAfterWd = IERC20(supplyToken).balanceOf(address(this));
            IERC20(supplyToken).transfer(msg.sender, balanceAfterWd - balanceBeforeWd);
        }

        ridesShares[_rideId] -= _amount;

        emit SharesRedeemed(_rideId, _amount);
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        return x <= y ? x : y;
    }
}
