// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IOnchainVaults.sol";
import "./interfaces/IOrderRegistry.sol";
import "./interfaces/IShareToken.sol";
import "./interfaces/IStrategyPool.sol";

/**
 * @title common broker
 */
contract Broker is Ownable {
    using Address for address;
    using SafeERC20 for IERC20;

    event PriceChanged(uint256 rideId, uint256 oldVal, uint256 newVal);
    event SlippageChanged(uint256 rideId, uint256 oldVal, uint256 newVal);
    event RideInfoRegistered(uint256 rideId, RideInfo rideInfo);
    event MintAndSell(uint256 rideId, uint256 mintShareAmt, uint256 price, uint256 slippage);
    event CancelSell(uint256 rideId, uint256 cancelShareAmt);
    event RideDeparted(uint256 rideId, uint256 usedInputTokenAmt);
    event SharesBurned(uint256 rideId, uint256 burnedShareAmt);
    event SharesRedeemed(uint256 rideId, uint256 redeemedShareAmt);
    event OnchainVaultsChanged(address oldAddr, address newAddr);

    address public onchainVaults;

    mapping (uint256=>uint256) public prices; // rideid=>price, price in decimal 1e6
    uint256 public constant PRICE_DECIMALS = 1e6;
    mapping (uint256=>uint256) public slippages; // rideid=>slippage, slippage in denominator 10000
    uint256 public constant SLIPPAGE_DENOMINATOR = 10000;

    // Starkex token id of this mint token

    struct RideInfo {
        address share;
        uint256 tokenIdShare;
        uint256 quantumShare; 
        address inputToken;
        uint256 tokenIdInput;
        uint256 quantumInput;
        address outputToken;
        uint256 tokenIdOutput;
        uint256 quantumOutput;

        address strategyPool; // 3rd defi pool
    }
    // rideid => RideInfo
    // rideId will also be used as vaultIdShare, vaultIdInput and vaultIdOutput,
    // this is easy to maintain and will assure funds from different rides won’t mix together and create weird edge cases
    mapping (uint256 => RideInfo) internal rideInfos; 

    mapping (uint256=>uint256) public ridesShares; // rideid=>amount
    mapping (uint256=>bool) public rideDeparted; // rideid=>bool
    
    uint256 private nonce;
    uint256 public constant EXP_TIME = 2e7; // expiration time stamp of the limit order 

    mapping (uint256=>uint256) actualPrices; //rideid=>actual price

    struct OrderAssetInfo {
        uint256 tokenId;
        uint256 quantizedAmt;
        uint256 vaultId;
    }

    /**
     * @dev Constructor
     */
    constructor(
        address _onchainVaults
    ) {
        onchainVaults = _onchainVaults;
    }

    /**
     * @notice can be set multiple times, will use latest when mintShareAndSell.
     */
    function setPrice(uint256 _rideId, uint256 _price) external onlyOwner {
        require(ridesShares[_rideId] == 0, "change forbidden once share starting to sell");

        uint256 oldVal = prices[_rideId];
        prices[_rideId] = _price;
        emit PriceChanged(_rideId, oldVal, _price);
    }

    /**
     * @notice price slippage allowance when executing strategy
     */
    function setSlippage(uint256 _rideId, uint256 _slippage) external onlyOwner {
        require(_slippage <= 10000, "invalid slippage");
        require(ridesShares[_rideId] == 0, "change forbidden once share starting to sell");

        uint256 oldVal = slippages[_rideId];
        slippages[_rideId] = _slippage;
        emit SlippageChanged(_rideId, oldVal, _slippage);
    }

    /**
     * @notice registers ride info
     */
    function addRideInfo(uint256 _rideId, uint256[3] memory _tokenIds, address[3] memory _tokens, address _strategyPool) external onlyOwner {
        require(_tokenIds[0] != 0, "invalid tokenIdShare");
        require(_tokenIds[1] != 0, "invalid tokenIdInput");
        require(_tokenIds[2] != 0, "invalid tokenIdOutput");

        require(_tokens[0] != address(0), "invalid share addr");
        require(_tokens[1] != address(0), "invalid input token addr");
        require(_tokens[2] != address(0), "invalid output token addr");

        require(_strategyPool != address(0), "invalid strategy pool addr");

        RideInfo memory rideInfo = rideInfos[_rideId];
        require(rideInfo.tokenIdInput == 0, "ride assets info registered already");

        _checkTokenRegistered(_tokenIds[0]);
        _checkTokenRegistered(_tokenIds[1]);
        _checkTokenRegistered(_tokenIds[2]);

        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        uint256 quantumShare = ocv.getQuantum(_tokenIds[0]);
        uint256 quantumInput = ocv.getQuantum(_tokenIds[1]);
        uint256 quantumOutput = ocv.getQuantum(_tokenIds[2]);
        rideInfo = RideInfo(_tokens[0], _tokenIds[0], quantumShare, _tokens[1], _tokenIds[1], 
            quantumInput,  _tokens[2], _tokenIds[2], quantumOutput, _strategyPool);
        rideInfos[_rideId] = rideInfo;
        emit RideInfoRegistered(_rideId, rideInfo);
    }

    /**
     * @notice mint share and sell for input token
     */
    function mintShareAndSell(uint256 _rideId, uint256 _amount, uint256 _tokenIdFee, uint256 _quantizedAmtFee, uint256 _vaultIdFee) external onlyOwner {
        RideInfo memory rideInfo = rideInfos[_rideId];
        require(rideInfo.tokenIdInput != 0, "ride assets info not registered");
        require(prices[_rideId] != 0, "price not set");
        require(slippages[_rideId] != 0, "slippage not set");
        require(ridesShares[_rideId] == 0, "already mint for this ride"); 
        _checkTokenRegistered(_tokenIdFee);

        IShareToken(rideInfo.share).mint(address(this), _amount);

        IERC20(rideInfo.share).safeIncreaseAllowance(onchainVaults, _amount);
        IOnchainVaults(onchainVaults).depositERC20ToVault(rideInfo.tokenIdShare, _rideId, _amount / rideInfo.quantumShare);
        
        _submitOrder(OrderAssetInfo(rideInfo.tokenIdShare, _amount / rideInfo.quantumShare, _rideId), 
            OrderAssetInfo(rideInfo.tokenIdInput, _amount / rideInfo.quantumInput, _rideId), OrderAssetInfo(_tokenIdFee, _quantizedAmtFee, _vaultIdFee));
        
        ridesShares[_rideId] = _amount;

        emit MintAndSell(_rideId, _amount, prices[_rideId], slippages[_rideId]);
    }

    /**
     * @notice cancel selling for input token
     */
    function cancelSell(uint256 _rideId, uint256 _tokenIdFee, uint256 _quantizedAmtFee, uint256 _vaultIdFee) external onlyOwner {
        uint256 amount = ridesShares[_rideId];
        require(amount > 0, "no shares to cancel sell"); 
        require(!rideDeparted[_rideId], "ride departed already");
        _checkTokenRegistered(_tokenIdFee);

        RideInfo memory rideInfo = rideInfos[_rideId]; //amount > 0 implies that the rideAssetsInfo already registered
        _submitOrder(OrderAssetInfo(rideInfo.tokenIdInput, amount / rideInfo.quantumInput, _rideId), 
            OrderAssetInfo(rideInfo.tokenIdShare, amount / rideInfo.quantumShare, _rideId), OrderAssetInfo(_tokenIdFee, _quantizedAmtFee, _vaultIdFee));

        emit CancelSell(_rideId, amount);
    }

    /**
     * @notice ride departure to execute strategy (swap input token for output token)
     * share : inputtoken = 1 : 1, outputtoken : share = price
     */
    function departRide(uint256 _rideId, uint256 _tokenIdFee, uint256 _quantizedAmtFee, uint256 _vaultIdFee) external onlyOwner {
        require(!rideDeparted[_rideId], "ride departed already");
        _checkTokenRegistered(_tokenIdFee);

        rideDeparted[_rideId] = true;

        burnRideShares(_rideId); //burn unsold shares
        uint256 amount = ridesShares[_rideId]; //get the left share amount
        require(amount > 0, "no shares to depart"); 
        
        RideInfo memory rideInfo = rideInfos[_rideId]; //amount > 0 implies that the rideAssetsInfo already registered
        IOnchainVaults ocv = IOnchainVaults(onchainVaults);

        uint256 inputTokenAmt;
        {
            uint256 inputTokenQuantizedAmt = ocv.getQuantizedVaultBalance(address(this), rideInfo.tokenIdInput, _rideId);
            assert(inputTokenQuantizedAmt > 0); 
            ocv.withdrawFromVault(rideInfo.tokenIdInput, _rideId, inputTokenQuantizedAmt);
            inputTokenAmt = inputTokenQuantizedAmt * rideInfo.quantumInput;
        }

        IERC20(rideInfo.inputToken).safeIncreaseAllowance(rideInfo.strategyPool, inputTokenAmt);
        uint256 outputAmt = IStrategyPool(rideInfo.strategyPool).sell(rideInfo.inputToken, rideInfo.outputToken, inputTokenAmt);
        {
            uint256 expectMinResult = amount * prices[_rideId] * (SLIPPAGE_DENOMINATOR - slippages[_rideId]) / PRICE_DECIMALS / SLIPPAGE_DENOMINATOR;
            require(outputAmt >= expectMinResult, "price and slippage not fulfilled");
            
            actualPrices[_rideId] = outputAmt * PRICE_DECIMALS / amount;
            IERC20(rideInfo.outputToken).approve(onchainVaults, outputAmt);
            ocv.depositERC20ToVault(rideInfo.tokenIdOutput, _rideId, outputAmt / rideInfo.quantumOutput);
        }

        _submitOrder(OrderAssetInfo(rideInfo.tokenIdOutput, outputAmt / rideInfo.quantumOutput, _rideId), 
            OrderAssetInfo(rideInfo.tokenIdShare, amount / rideInfo.quantumShare, _rideId), OrderAssetInfo(_tokenIdFee, _quantizedAmtFee, _vaultIdFee));

        emit RideDeparted(_rideId, inputTokenAmt);
    }

    /**
     * @notice burn ride shares after ride is done
     */
    function burnRideShares(uint256 _rideId) public {
        uint256 amount = ridesShares[_rideId];
        require(amount > 0, "no shares to burn"); 
        
        RideInfo memory rideInfo = rideInfos[_rideId]; //amount > 0 implies that the rideAssetsInfo already registered
        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        uint256 quantizedAmountToBurn = ocv.getQuantizedVaultBalance(address(this), rideInfo.tokenIdShare, _rideId);
        require(quantizedAmountToBurn > 0, "no shares to burn");

        ocv.withdrawFromVault(rideInfo.tokenIdShare, _rideId, quantizedAmountToBurn);

        uint256 burnAmt = quantizedAmountToBurn * rideInfo.quantumShare;
        ridesShares[_rideId] = amount - burnAmt; // update to left amount
        IShareToken(rideInfo.share).burn(address(this), burnAmt);

        emit SharesBurned(_rideId, burnAmt);
    }

    /**
     * @notice user to redeem share for input or output token 
     * input token when ride has not been departed, otherwise, output token
     */
    function redeemShare(uint256 _rideId, uint256 _redeemAmount) external {
        uint256 amount = ridesShares[_rideId];
        require(amount > 0, "no shares to redeem");

        RideInfo memory rideInfo = rideInfos[_rideId]; //amount > 0 implies that the rideAssetsInfo already registered

        IERC20(rideInfo.share).safeTransferFrom(msg.sender, address(this), _redeemAmount);

        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        bool departed = rideDeparted[_rideId];
        if (departed) {
            //swap to output token
            uint256 boughtAmt = _redeemAmount * actualPrices[_rideId] / PRICE_DECIMALS;            
            ocv.withdrawFromVault(rideInfo.tokenIdOutput, _rideId, boughtAmt / rideInfo.quantumOutput);
            IERC20(rideInfo.outputToken).safeTransfer(msg.sender, boughtAmt);
        } else {
            //swap to input boken
            ocv.withdrawFromVault(rideInfo.tokenIdInput, _rideId, _redeemAmount / rideInfo.quantumInput);
            IERC20(rideInfo.inputToken).safeTransfer(msg.sender, _redeemAmount);
        }

        ridesShares[_rideId] -= _redeemAmount;
        IShareToken(rideInfo.share).burn(address(this), _redeemAmount);

        emit SharesRedeemed(_rideId, _redeemAmount);
    }

    function _checkTokenRegistered(uint256 tokenId) view internal {
        bool tokenRegistered = IOnchainVaults(onchainVaults).registeredAssetType(tokenId);
        require(tokenRegistered, "token not registered to Starkex");
    }

    function _submitOrder(OrderAssetInfo memory sellInfo, OrderAssetInfo memory buyInfo, OrderAssetInfo memory feeInfo) private {
        nonce += 1;
        address orderRegistryAddr = IOnchainVaults(onchainVaults).orderRegistryAddress();
        IOrderRegistry(orderRegistryAddr).registerLimitOrder(onchainVaults, sellInfo.tokenId, buyInfo.tokenId, feeInfo.tokenId, 
            sellInfo.quantizedAmt, buyInfo.quantizedAmt, feeInfo.quantizedAmt, sellInfo.vaultId, buyInfo.vaultId, feeInfo.vaultId, nonce, EXP_TIME);
    }

    function setOnchainVaults(address _newAddr) external onlyOwner {
        emit OnchainVaultsChanged(onchainVaults, _newAddr);
        onchainVaults = _newAddr;
    }
}
