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

    mapping (uint256=>uint256) public prices; // rideid=>price, price in decimal 1e18
    uint256 public constant PRICE_DECIMALS = 1e18;
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
    mapping(uint256 => RideAssetsInfo) internal rideAssetsInfos; //rideid => RideAssetsInfo

    mapping (uint256=>uint256) public ridesShares; // rideid=>amount

    /**
     * @dev Constructor that gives msg.sender an initial supply of tokens.
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 decimals_,
        uint256 _initialSupply,
        address _exchange,
        address _orderRegistry,
        address _onchainVaults
    ) ERC20(_name, _symbol) {
        _decimals = decimals_;
        exchange = _exchange;
        orderRegistry = _orderRegistry;
        onchainVaults = _onchainVaults;
        _mint(msg.sender, _initialSupply);
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
        prices[_rideId] = _slippage;
    }

    function addRideAssetsInfo(uint256 _rideId, uint256[] memory _assetsInfo) external onlyOwner {
        require(_assetsInfo.length == 9, "worng ride assets info");
        require(_assetsInfo[0] != 0, "wrong tokenIdShare");
        require(_assetsInfo[1] != 0, "wrong vaultIdShare");
        require(_assetsInfo[2] != 0, "wrong quantumShare");
        require(_assetsInfo[3] != 0, "wrong tokenIdInput");
        require(_assetsInfo[4] != 0, "wrong vaultIdInput");
        require(_assetsInfo[5] != 0, "wrong quantumInput");
        require(_assetsInfo[6] != 0, "wrong tokenIdOutput");
        require(_assetsInfo[7] != 0, "wrong vaultIdOutput");
        require(_assetsInfo[8] != 0, "wrong quantumOutput");
        RideAssetsInfo memory assetsInfo = RideAssetsInfo(_assetsInfo[0], _assetsInfo[1], _assetsInfo[2],
            _assetsInfo[3], _assetsInfo[4], _assetsInfo[5], _assetsInfo[6], _assetsInfo[7], _assetsInfo[8]);
        rideAssetsInfos[_rideId] = assetsInfo;
    }

    /**
     * @notice 
     */
    function mintAndSell(uint256 _rideId, uint256 _amount, uint256 _tokenIdFee, uint256 _amountFee, uint256 _vaultIdFee) virtual external;

    /**
     * @notice 
     */
    function cancelSell(uint256 _rideId, uint256 _amount) virtual external;

    /**
     * @notice 
     */
    function departRide(uint256 _rideId) virtual external;

    /**
     * @notice 
     */
    function burnRideShares(uint256 _rideId) virtual external;

    /**
     * @notice 
     */
    function redeemShare(uint256 _amount) virtual external;

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
