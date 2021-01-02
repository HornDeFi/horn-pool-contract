// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "./HornLockVault.sol";
import "./HornToken.sol";
import "./interfaces/IExtendedERC20.sol";

contract UnifiedHornVault {
    address private _owner;
    address private _hornTokenAddr;
    HornToken private _hornToken;

    address[] public vaultIndexes;

    modifier onlyOwner() {
        require(msg.sender == _owner, "Only the owner can do this action");
        _;
    }

    constructor(address hornTokenAddr) {
        _owner = msg.sender;
        _hornTokenAddr = hornTokenAddr;
        _hornToken = HornToken(hornTokenAddr);
    }

    function fetchIndexes() public view returns (address[] memory) {
        address[] memory result = new address[](vaultIndexes.length);
        for (uint256 i = 0; i < vaultIndexes.length; i++) {
            result[i] = vaultIndexes[i];
        }
        return result;
    }

    function addPool(
        address lockedTokenAddr,
        address hornTokenAddr,
        uint128 fee,
        uint128 depositRewardFee,
        uint256 hornPerDay,
        uint256 minLockDays,
        uint256 weightPerHorn
    ) public payable onlyOwner returns (address) {
        // Create the vault
        HornLockVault vault =
            new HornLockVault(
                msg.sender,
                lockedTokenAddr,
                hornTokenAddr,
                fee,
                depositRewardFee,
                hornPerDay,
                minLockDays,
                weightPerHorn
            );
        _hornToken.grantRole(_hornToken.MINTER_ROLE(), address(vault));
        _hornToken.grantRole(_hornToken.BURNER_ROLE(), address(vault));
        vault.setActiveState(true);

        // add the index to the array
        vaultIndexes.push(address(vault));

        return address(vault);
    }

    function addExistingPool(address addr)
        public
        payable
        onlyOwner
        returns (address)
    {
        vaultIndexes.push(addr);
        return addr;
    }

    function removePool(address addr) public payable onlyOwner {
        HornLockVault vault = HornLockVault(addr);
        vault.setActiveState(false);

        address[] memory newArray = new address[](vaultIndexes.length - 1);
        uint256 new_index = 0;
        for (uint256 i = 0; i < vaultIndexes.length; i++) {
            if (vaultIndexes[i] != addr) {
                newArray[new_index++] = vaultIndexes[i];
            }
        }
        vaultIndexes = newArray;
    }
}
