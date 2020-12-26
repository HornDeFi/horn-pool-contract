// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

interface IHornLockVault {
    function balanceOf(address account) external view returns (uint256);
    function claimableBalanceOf(address account) external view returns (uint256);
    function claimableHornOf(address account) external view returns (uint256);
    function deposit(uint256 amount, address referralAddr) external payable returns(bool);
    function withdraw() external payable returns(bool);
    function burn(uint256 amount) external payable returns(bool);
    function reserve() external view returns (uint256);
    function lockedAssets() external view returns (uint256);
    
    event Deposit(address indexed from, uint256 value, uint256 fee, uint256 fromDate, uint256 toDate);
    event Withdraw(address indexed to, uint256 value);
    event Burn(address indexed from, uint256 value, uint256 weightAdded);
    event DepositReward(address indexed to, uint256 reward, uint256 totalFee, uint256 senderBalance, uint256 contractBalance, uint256 weightPercent);
    event ReferralReward(address indexed from, address indexed to, uint256 amount, uint256 reward, uint256 baseFee);
    event NewPool(uint256 index, uint256 timestamp);
    event Claim(address indexed from, uint256 amount);
    event Log(string text);
    event LogUINT(uint256 value);
    event LogUINTText(string key, uint256 value);
    event LogAddress(address value);
}