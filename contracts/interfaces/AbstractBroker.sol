// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IOnchainVaults.sol";

/**
 * @title abstract DeFi broker pool, as the parent of actual broker contracts, such as compound broker pool, aave broker pool etc
 */
abstract contract AbstractBroker is ERC20Burnable, Ownable {
    event PriceChange(uint256 rideId, uint256 oldVal, uint256 newVal);
    event SlippageChange(uint256 rideId, uint256 oldVal, uint256 newVal);
    event RideAssetsInfoRegistered(uint256 rideId, RideAssetsInfo assetsInfo);
    event MintAndSell(uint256 rideId, uint256 mintShareAmt, uint256 price, uint256 slippage);
    event CancelSell(uint256 rideId, uint256 cancelShareAmt);
    event RideDeparted(uint256 rideId, uint256 usedInputTokenAmt);
    event SharesBurned(uint256 rideId, uint256 burnedShareAmt);
    event SharesRedeemed(uint256 rideId, uint256 redeemedShareAmt);

    uint8 private _decimals;
    address public onchainVaults;

    mapping (uint256=>uint256) public prices; // rideid=>price, price in decimal 1e6
    uint256 public constant PRICE_DECIMALS = 1e6;
    mapping (uint256=>uint256) public slippages; // rideid=>slippage, slippage in denominator 10000
    uint256 public constant SLIPPAGE_DENOMINATOR = 10000;

    // Starkex token id of this mint token
    uint256 public tokenIdShare;
    uint256 public quantumShare; 
    struct RideAssetsInfo {
        uint256 tokenIdInput;
        uint256 quantumInput;
        uint256 tokenIdOutput;
        uint256 quantumOutput;
    }
    // rideid => RideAssetsInfo
    // rideId will also be used as vaultIdShare, vaultIdInput and vaultIdOutput,
    // this is easy to maintain and will assure funds from different rides won’t mix together and create weird edge cases
    mapping (uint256 => RideAssetsInfo) internal rideAssetsInfos; 

    mapping (uint256=>uint256) public ridesShares; // rideid=>amount
    mapping (uint256=>bool) public rideDeparted; // rideid=>bool

    /**
     * @dev Constructor
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 decimals_,
        address _onchainVaults,
        uint256 _tokenIdShare
    ) ERC20(_name, _symbol) {
        onchainVaults = _onchainVaults;
        _checkTokenRegistered(_tokenIdShare);

        _decimals = decimals_;
        tokenIdShare = _tokenIdShare;
        quantumShare = IOnchainVaults(onchainVaults).getQuantum(tokenIdShare);
    }

    /**
     * @notice can be set multiple times, will use latest when mintShareAndSell.
     */
    function setPrice(uint256 _rideId, uint256 _price) external onlyOwner {
        require(ridesShares[_rideId] == 0, "change forbidden once share starting to sell");

        uint256 oldVal = prices[_rideId];
        prices[_rideId] = _price;
        emit PriceChange(_rideId, oldVal, _price);
    }

    /**
     * @notice price slippage allowance when executing strategy
     */
    function setSlippage(uint256 _rideId, uint256 _slippage) external onlyOwner {
        require(_slippage <= 10000, "invalid slippage");
        require(ridesShares[_rideId] == 0, "change forbidden once share starting to sell");

        uint256 oldVal = slippages[_rideId];
        slippages[_rideId] = _slippage;
        emit SlippageChange(_rideId, oldVal, _slippage);
    }

    /**
     * @notice registers assets info of a ride
     */
    function addRideAssetsInfo(uint256 _rideId, uint256 _tokenIdInput, uint256 _tokenIdOutput) external onlyOwner {
        require(_tokenIdInput != 0, "invalid tokenIdInput");
        require(_tokenIdOutput != 0, "invalid tokenIdOutput");

        RideAssetsInfo memory assetsInfo = rideAssetsInfos[_rideId];
        require(assetsInfo.tokenIdInput == 0, "ride assets info registered already");

        _checkTokenRegistered(_tokenIdInput);
        _checkTokenRegistered(_tokenIdOutput);

        IOnchainVaults ocv = IOnchainVaults(onchainVaults);
        uint256 quantumInput = ocv.getQuantum(_tokenIdInput);
        uint256 quantumOutput = ocv.getQuantum(_tokenIdOutput);
        assetsInfo = RideAssetsInfo(_tokenIdInput, quantumInput, _tokenIdOutput, quantumOutput);
        rideAssetsInfos[_rideId] = assetsInfo;
        emit RideAssetsInfoRegistered(_rideId, assetsInfo);
    }

    /**
     * @notice mint share and sell for input token
     */
    function mintShareAndSell(uint256 _rideId, uint256 _amount, uint256 _tokenIdFee, uint256 _quantizedAmtFee, uint256 _vaultIdFee) virtual external;

    /**
     * @notice cancel selling for input token
     */
    function cancelSell(uint256 _rideId, uint256 _tokenIdFee, uint256 _quantizedAmtFee, uint256 _vaultIdFee) virtual external;

    /**
     * @notice ride departure to execute strategy (swap input token for output token)
     */
    function departRide(uint256 _rideId, uint256 _tokenIdFee, uint256 _quantizedAmtFee, uint256 _vaultIdFee) virtual external;

    /**
     * @notice burn ride shares after ride is done
     */
    function burnRideShares(uint256 _rideId) virtual public;

    /**
     * @notice user to redeem share for input or output token 
     * input token when ride has not been departed, otherwise, output token
     */
    function redeemShare(uint256 _rideId, uint256 _amount) virtual external;

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function _checkTokenRegistered(uint256 tokenId) view internal {
        bool tokenRegistered = IOnchainVaults(onchainVaults).registeredAssetType(tokenId);
        require(tokenRegistered, "token not registered to Starkex");
    }
}
