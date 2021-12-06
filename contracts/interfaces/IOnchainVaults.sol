// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

interface IOnchainVaults {
    function depositERC20ToVault(
        uint256 assetId,
        uint256 vaultId,
        uint256 quantizedAmount
    ) external;

    function withdrawFromVault(
        uint256 assetId,
        uint256 vaultId,
        uint256 quantizedAmount
    ) external;
}