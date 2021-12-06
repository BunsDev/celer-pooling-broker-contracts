// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title abstract DeFi broker pool
 */
abstract contract AbstractBroker is ERC20Burnable, Ownable {
    uint8 private _decimals;
    address public exchange;
    address public orderRegistry;
    address public onchainVaults;

    mapping (uint256=>uint256) public prices; // rideid=>price, price in decimal 1e6
    uint256 public constant PRICE_DECIMALS = 1e6;
    mapping (uint256=>uint256) public slippages; // rideid=>slippage, slippage in denominator 10000
    uint256 public constant SLIPPAGE_DENOMINATOR = 10000;
    struct RideAssetsInfo {
        uint256 tokenIdShare;
        uint256 vaultIdShare;
        uint256 quantumShare;
        uint256 tokenIdInput;
        uint256 vaultIdInput;
        uint256 quantumInput;
        uint256 tokenIdOutput;
        uint256 vaultIdOutput;
        uint256 quantumOutput;
    }
    mapping (uint256 => RideAssetsInfo) internal rideAssetsInfos; //rideid => RideAssetsInfo

    mapping (uint256=>uint256) public ridesShares; // rideid=>amount
    mapping (uint256=>bool) public rideDeparted; // rideid=>bool

    /**
     * @dev Constructor
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 decimals_,
        address _exchange,
        address _orderRegistry,
        address _onchainVaults
    ) ERC20(_name, _symbol) {
        _decimals = decimals_;
        exchange = _exchange;
        orderRegistry = _orderRegistry;
        onchainVaults = _onchainVaults;
    }

    /**
     * @notice 
     */
    function setPrice(uint256 _rideId, uint256 _price) external onlyOwner {
        prices[_rideId] = _price;
    }

    /**
     * @notice 
     */
    function setSlippage(uint256 _rideId, uint256 _slippage) external onlyOwner {
        require(_slippage <= 10000, "invalid slippage");
        prices[_rideId] = _slippage;
    }

    function addRideAssetsInfo(uint256 _rideId, uint256[] memory _assetsInfo) external onlyOwner {
        require(_assetsInfo.length == 9, "invalid ride assets info");
        require(_assetsInfo[0] != 0, "invalid tokenIdShare");
        require(_assetsInfo[1] != 0, "invalid vaultIdShare");
        require(_assetsInfo[2] != 0, "invalid quantumShare");
        require(_assetsInfo[3] != 0, "invalid tokenIdInput");
        require(_assetsInfo[4] != 0, "invalid vaultIdInput");
        require(_assetsInfo[5] != 0, "invalid quantumInput");
        require(_assetsInfo[6] != 0, "invalid tokenIdOutput");
        require(_assetsInfo[7] != 0, "invalid vaultIdOutput");
        require(_assetsInfo[8] != 0, "invalid quantumOutput");
        RideAssetsInfo memory assetsInfo = RideAssetsInfo(_assetsInfo[0], _assetsInfo[1], _assetsInfo[2],
            _assetsInfo[3], _assetsInfo[4], _assetsInfo[5], _assetsInfo[6], _assetsInfo[7], _assetsInfo[8]);
        rideAssetsInfos[_rideId] = assetsInfo;
    }

    /**
     * @notice 
     */
    function mintShareAndSell(uint256 _rideId, uint256 _amount, uint256 _tokenIdFee, uint256 _amountFee, uint256 _vaultIdFee) virtual external;

    /**
     * @notice 
     */
    function cancelSell(uint256 _rideId, uint256 _tokenIdFee, uint256 _amountFee, uint256 _vaultIdFee) virtual external;

    /**
     * @notice 
     */
    function departRide(uint256 _rideId, uint256 _tokenIdFee, uint256 _amountFee, uint256 _vaultIdFee) virtual external;

    /**
     * @notice 
     */
    function burnRideShares(uint256 _rideId) virtual public;

    /**
     * @notice 
     */
    function redeemShare(uint256 _rideId, uint256 _amount) virtual external;

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
