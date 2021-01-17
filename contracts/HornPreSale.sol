// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "./HornLockVault_v2.sol";
import "./HornToken.sol";
import "./interfaces/IExtendedERC20.sol";

contract HornPreSale {
    uint256 public _hornPerEther = 5000000000000000000000;
    uint256 public _maxHornForPresale;
    uint256 public _hornSolded;
    bool public _paused = false;
    address private _owner;
    IExtendedERC20 private _hornToken;

    address internal _wethTokenAddress;

    constructor(address hornTokenAddr, uint256 maxHornForPresale, address wethTokenAddress, uint256 hornPerEther) {
        _owner = msg.sender;
        _hornSolded = 0;
        _hornPerEther = hornPerEther;
        _wethTokenAddress = wethTokenAddress;
        _maxHornForPresale = maxHornForPresale;
        _hornToken = IExtendedERC20(hornTokenAddr);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Only the owner can do this action");
        _;
    }

    function setMaxHornForPresale(uint256 value) public payable onlyOwner {
        _maxHornForPresale = value;
    }

    function setHornPerEther(uint256 value) public payable onlyOwner {
        _hornPerEther = value;
    }

    function setPaused(bool value) public payable onlyOwner {
        _paused = value;
    }
    
    function withdraw() public payable onlyOwner {
        IERC20 wethToken = IERC20(_wethTokenAddress);
        wethToken.transfer(msg.sender, wethToken.balanceOf(address(this)));
        msg.sender.transfer(address(this).balance);
    }

    receive() external payable {
        require(_paused == false, "Presale is paused");
        _mintAndTransferHorn(msg.value, msg.sender);
    }

    function transferToken(uint256 _amount) public payable {
        require(_paused == false, "Presale is paused");
        IERC20 token = IERC20(_wethTokenAddress);

        // Remove wether from the sender
        require(
            _amount > 0,
            "Invalid amount"
        );
        require(
            token.balanceOf(msg.sender) >= _amount,
            "No WETH amount required"
        );
        require(
            token.transferFrom(msg.sender, address(this), _amount) == true,
            "Can't transfert WETH on the contract"
        );

        _mintAndTransferHorn(_amount, msg.sender);
    }

    function _mintAndTransferHorn(uint256 inAmount, address sender) internal {
        uint256 hornAmount = inAmount * _hornPerEther;
        require(_hornSolded + hornAmount <= _maxHornForPresale, "The limit of the presale has been reached, try buy less horn");
        _hornToken.mint(address(this), hornAmount);
        _hornSolded = _hornSolded + hornAmount;
        require(
            _hornToken.transfer(sender, hornAmount) == true,
            "Error transferFrom on the contract"
        );
    }
}
