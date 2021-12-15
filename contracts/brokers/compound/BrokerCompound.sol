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
    address public immutable inputToken; // address of input token
    
    uint256 nonce;
    uint256 constant EXP_TIME = 2e7; // expiration time stamp of the limit order 

    mapping (uint256=>uint256) actualPrices; //rideid=>actual price

    struct OrderAssetInfo {
        uint256 tokenId;
        uint256 quantizedAmt;
        uint256 vaultId;
    }

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        address _onchainVaults,
        uint256 _tokenIdShare,
        address _cErc20,
        address _inputToken
    ) AbstractBroker(_name, _symbol, _decimals, _onchainVaults, _tokenIdShare) {
        cErc20 = _cErc20;
        inputToken = _inputToken;
    }

    /**
     * @notice 
     */
    function mintShareAndSell(uint256 _rideId, uint256 _amount, uint256 _tokenIdFee, uint256 _quantizedAmtFee, uint256 _vaultIdFee) override external onlyOwner {

        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId];
        require(rideAssetsInfo.tokenIdInput != 0, "ride assets info not registered");
        require(prices[_rideId] != 0, "price not set");
        require(slippages[_rideId] != 0, "slippage not set");
        require(ridesShares[_rideId] == 0, "already mint for this ride"); 
        _checkTokenRegistered(_tokenIdFee);

        _mint(address(this), _amount);

        IERC20(this).safeIncreaseAllowance(onchainVaults, _amount);
        IOnchainVaults(onchainVaults).depositERC20ToVault(tokenIdShare, _rideId, _amount / quantumShare);
        
        _submitOrder(OrderAssetInfo(tokenIdShare, _amount / quantumShare, _rideId), 
            OrderAssetInfo(rideAssetsInfo.tokenIdInput, _amount / rideAssetsInfo.quantumInput, _rideId), OrderAssetInfo(_tokenIdFee, _quantizedAmtFee, _vaultIdFee));
        
        ridesShares[_rideId] = _amount;

        emit MintAndSell(_rideId, _amount, prices[_rideId], slippages[_rideId]);
    }

    function _submitOrder(OrderAssetInfo memory sellInfo, OrderAssetInfo memory buyInfo, OrderAssetInfo memory feeInfo) private {
        nonce += 1;
        address orderRegistryAddr = IOnchainVaults(onchainVaults).orderRegistryAddress();
        IOrderRegistry(orderRegistryAddr).registerLimitOrder(onchainVaults, sellInfo.tokenId, buyInfo.tokenId, feeInfo.tokenId, 
            sellInfo.quantizedAmt, buyInfo.quantizedAmt, feeInfo.quantizedAmt, sellInfo.vaultId, buyInfo.vaultId, feeInfo.vaultId, nonce, EXP_TIME);
    }

    /**
     * @notice 
     */
    function cancelSell(uint256 _rideId, uint256 _tokenIdFee, uint256 _quantizedAmtFee, uint256 _vaultIdFee) override external onlyOwner {
        uint256 amount = ridesShares[_rideId];
        require(amount > 0, "no shares to cancel sell"); 
        require(!rideDeparted[_rideId], "ride departed already");
        _checkTokenRegistered(_tokenIdFee);

        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId]; //amount > 0 implies that the rideAssetsInfo already registered
        _submitOrder(OrderAssetInfo(rideAssetsInfo.tokenIdInput, amount / rideAssetsInfo.quantumInput, _rideId), 
            OrderAssetInfo(tokenIdShare, amount / quantumShare, _rideId), OrderAssetInfo(_tokenIdFee, _quantizedAmtFee, _vaultIdFee));

        emit CancelSell(_rideId, amount);
    }

    /**
     * @notice 
     * share : inputtoken = 1 : 1, outputtoken : share = price
     */
    function departRide(uint256 _rideId, uint256 _tokenIdFee, uint256 _quantizedAmtFee, uint256 _vaultIdFee) override external onlyOwner {
        require(!rideDeparted[_rideId], "ride departed already");
        _checkTokenRegistered(_tokenIdFee);

        rideDeparted[_rideId] = true;

        burnRideShares(_rideId); //burn unsold shares
        uint256 amount = ridesShares[_rideId]; //get the left share amount
        require(amount > 0, "no shares to depart"); 
        
        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId]; //amount > 0 implies that the rideAssetsInfo already registered
        IOnchainVaults ocv = IOnchainVaults(onchainVaults);

        uint256 inputTokenAmt;
        {
            uint256 inputTokenQuantizedAmt = ocv.getQuantizedVaultBalance(address(this), rideAssetsInfo.tokenIdInput, _rideId);
            assert(inputTokenQuantizedAmt > 0); 
            ocv.withdrawFromVault(rideAssetsInfo.tokenIdInput, _rideId, inputTokenQuantizedAmt);
            inputTokenAmt = inputTokenQuantizedAmt * rideAssetsInfo.quantumInput;
        }

        IERC20(inputToken).safeIncreaseAllowance(cErc20, inputTokenAmt);
        uint256 ctokenAmt = ICErc20(cErc20).mint(inputTokenAmt);
        {
            uint256 expectMinResult = amount * prices[_rideId] * (SLIPPAGE_DENOMINATOR - slippages[_rideId]) / PRICE_DECIMALS / SLIPPAGE_DENOMINATOR;
            require(ctokenAmt >= expectMinResult, "price and slippage not fulfilled");
            
            actualPrices[_rideId] = ctokenAmt * PRICE_DECIMALS / amount;
            ICErc20(cErc20).approve(onchainVaults, ctokenAmt);
            ocv.depositERC20ToVault(rideAssetsInfo.tokenIdOutput, _rideId, ctokenAmt / rideAssetsInfo.quantumOutput);
        }

        _submitOrder(OrderAssetInfo(rideAssetsInfo.tokenIdOutput, ctokenAmt / rideAssetsInfo.quantumOutput, _rideId), 
            OrderAssetInfo(tokenIdShare, amount / quantumShare, _rideId), OrderAssetInfo(_tokenIdFee, _quantizedAmtFee, _vaultIdFee));

        emit RideDeparted(_rideId, inputTokenAmt);
    }

    /**
     * @notice 
     */
    function burnRideShares(uint256 _rideId) override public onlyOwner {
        uint256 amount = ridesShares[_rideId];
        require(amount > 0, "no shares to burn"); 
        
        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        uint256 quantizedAmountToBurn = ocv.getQuantizedVaultBalance(address(this), tokenIdShare, _rideId);
        require(quantizedAmountToBurn > 0, "no shares to burn");

        ocv.withdrawFromVault(tokenIdShare, _rideId, quantizedAmountToBurn);

        uint256 burnAmt = quantizedAmountToBurn * quantumShare;
        ridesShares[_rideId] = amount - burnAmt; // update to left amount
        _burn(address(this), burnAmt);

        emit SharesBurned(_rideId, burnAmt);
    }

    /**
     * @notice 
     * TODO: where to maintain the user list of a ride, in order to check if the caller is the ride user? 
     */
    function redeemShare(uint256 _rideId, uint256 _redeemAmount) override external {
        uint256 amount = ridesShares[_rideId];
        require(amount > 0, "no shares to redeem");

        RideAssetsInfo memory rideAssetsInfo = rideAssetsInfos[_rideId]; //amount > 0 implies that the rideAssetsInfo already registered

        IERC20(this).safeTransferFrom(msg.sender, address(this), _redeemAmount);

        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        bool departed = rideDeparted[_rideId];
        if (departed) {
            //swap to output token
            uint256 boughtAmt = _redeemAmount * actualPrices[_rideId] / PRICE_DECIMALS;            
            ocv.withdrawFromVault(rideAssetsInfo.tokenIdOutput, _rideId, boughtAmt / rideAssetsInfo.quantumOutput);
            ICErc20(cErc20).transfer(msg.sender, boughtAmt);
        } else {
            //swap to input boken
            ocv.withdrawFromVault(rideAssetsInfo.tokenIdInput, _rideId, _redeemAmount / rideAssetsInfo.quantumInput);
            IERC20(inputToken).transfer(msg.sender, _redeemAmount);
        }

        ridesShares[_rideId] -= _redeemAmount;
        _burn(address(this), _redeemAmount);

        emit SharesRedeemed(_rideId, _redeemAmount);
    }
}
