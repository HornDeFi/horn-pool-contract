// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IHornLockVault.sol";
import "./interfaces/IExtendedERC20.sol";

contract HornLockVault is IHornLockVault {
    using SafeMath for uint256;

    struct LockedAsset {
        address account;
        uint256 amount;
        uint256 burnedHorn;
        uint256 fees;
        uint256 fromDate;
        uint256 toDate;
        address referralAddr;
        uint256 poolIndex;
        uint256 alreadyClaimedHorn;
        bool isBurnAsset;
        uint256 baseAmount;
        uint256 enterPoolFees;
    }

    struct RewardFee {
        uint256 amount;
        uint256 depositDate;
    }
    
    LockedAsset[] private _lockedAssets;
    mapping(uint256 => RewardFee) private _poolFees;

    address private _owner;
    string private _vaultName;
    uint128 private _fee;
    uint128 private _depositRewardFee;
    uint256 private _hornPerDay;
    uint256 private _feesVault;
    uint256 private _minLockDays;
    uint256 private _currentFeeIndex = 0;
    uint256 private _weightPerHorn;
    bool private _isPaused = false;
    bool private _hornRewardDisabled = false;
    bool private _emergencyWithdraw = false;
    IExtendedERC20 private _token;
    IExtendedERC20 private _hornToken;

    constructor(address lockedTokenAddr, address hornTokenAddr, uint128 fee,
        uint128 depositRewardFee, uint256 hornPerDay, uint256 minLockDays, uint256 weightPerHorn) {
        _owner = msg.sender;
        _token = IExtendedERC20(lockedTokenAddr);
        _hornToken = IExtendedERC20(hornTokenAddr);
        _vaultName = _token.symbol();
        _fee = fee;
        _depositRewardFee = depositRewardFee;
        _hornPerDay = hornPerDay;
        _minLockDays = minLockDays;
        _weightPerHorn = weightPerHorn;

        _poolFees[_currentFeeIndex].amount = 0;
        _poolFees[_currentFeeIndex].depositDate = block.timestamp.add(1 days);
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i++) {
            if(_lockedAssets[i].isBurnAsset) continue;
            if(account == _lockedAssets[i].account) {
                totalBalance = totalBalance.add(_lockedAssets[i].amount);
            }
        }
        return totalBalance;
    }

    function claimableBalanceOf(address account) public view override returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i++) {
            if(_lockedAssets[i].isBurnAsset) continue;
            if(account == _lockedAssets[i].account && _lockedAssets[i].toDate <= block.timestamp) {
                totalBalance = totalBalance.add(_lockedAssets[i].amount);
            }
        }
        return totalBalance;
    }

    function claimableHornOf(address account) public view override returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i++) {
            if(account == _lockedAssets[i].account && _lockedAssets[i].amount > 0 && !_lockedAssets[i].isBurnAsset) {
                LockedAsset memory asset =  _lockedAssets[i];
                uint256 period = block.timestamp.sub(asset.fromDate).div(60).div(60).div(24);
                if(period <= 0) continue;
                uint256 reward = _hornPerDay.mul(asset.amount.mul(100)).div(10000).mul(period);
                reward = reward.div(100).sub(asset.alreadyClaimedHorn);
                totalBalance = totalBalance.add(reward);
            }
        }
        return totalBalance;
    }

    function reserve() public view override returns (uint256) {
        return _hornToken.balanceOf(address(this));
    }

    function lockedAssets() public view override returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i++) {
            if(_lockedAssets[i].isBurnAsset) continue;
            totalBalance = totalBalance.add(_lockedAssets[i].amount);
        }
        return totalBalance;
    }
    
    function lockedAssetsBefore(uint256 before) public view returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i++) {
            if(_lockedAssets[i].fromDate <= before) {
                totalBalance = totalBalance.add(_lockedAssets[i].amount);
            }
        }
        return totalBalance;
    }

    function getBurnedHornAmount(address account) public view returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i++) {
            if(account == _lockedAssets[i].account && _lockedAssets[i].isBurnAsset) {
                totalBalance = totalBalance.add(_lockedAssets[i].burnedHorn);
            }
        }
        return totalBalance;
    }

    function name() public view returns (string memory) {
        return _vaultName;
    }

    function setPauseState(bool newState) external payable returns(bool) {
        require(msg.sender == _owner, "Only the owner can do this");
        _isPaused = newState;
        return true;
    }

    function setHornRewardDisabledState(bool newState) external payable returns(bool) {
        require(msg.sender == _owner, "Only the owner can do this");
        _hornRewardDisabled = newState;
        return true;
    }
    
    function setEmergencyWithdrawState(bool newState) external payable returns(bool) {
        require(msg.sender == _owner, "Only the owner can do this");
        _emergencyWithdraw = newState;
        return true;
    }

    function deposit(uint256 amount, address referralAddr) external payable override returns(bool) {
        require(amount > 0, "Invalid amount");
        require(!_isPaused, "Deposit are paused for now");
        _deposit(msg.sender, amount, referralAddr);
        return true;
    }

    function balanceIndexes(address account, bool filterBurned) public view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i++) {
            if(_lockedAssets[i].account == account && _lockedAssets[i].amount > 0 && _lockedAssets[i].isBurnAsset == filterBurned) {
                count++;
            }
        }
        uint256[] memory indexes = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i++) {
            if(_lockedAssets[i].account == account && _lockedAssets[i].amount > 0 && _lockedAssets[i].isBurnAsset == filterBurned) {
                indexes[index] = i;
                index++;
            }
        }
        return indexes;
    }

    function getLockedAssetsCountByAccount(address account) public view returns (uint256) {
        uint256 count = 0;
         for (uint256 i = 0; i < _lockedAssets.length; i++) {
            if(_lockedAssets[i].account == account && _lockedAssets[i].amount > 0) {
                count++;
            }
        }
        return count;
    }

    function claimableFees(address account, uint256 index) public view returns(uint256) {
        uint256 totalFees = 0;
        LockedAsset memory asset = _lockedAssets[index];
        if(asset.account == account && asset.amount > 0) {
            for (uint256 y = 0; y < _currentFeeIndex + 1; y++) {
                if(_poolFees[y].depositDate >= asset.fromDate && _poolFees[y].amount > 0) {
                    uint256 contractBalance = lockedAssetsBefore(_poolFees[y].depositDate);
                    if(asset.fees > _poolFees[y].amount) continue;
                    uint256 fees = _poolFees[y].amount;
                    if(y == asset.poolIndex) {
                        if(asset.enterPoolFees > 0 && fees >= asset.enterPoolFees) {
                            fees = fees.sub(asset.enterPoolFees);
                        }
                        else if(asset.enterPoolFees > 0 && fees < asset.enterPoolFees) {
                            continue;
                        }
                    }
                    uint256 senderBalance = asset.amount;
                    uint256 weightPercent = senderBalance.mul(10000).div(contractBalance).mul(100);
                    uint256 reward = fees.mul(weightPercent).div(1000000);
                    totalFees = totalFees.add(reward);
                }
            }
        }
        return totalFees;
    }

    function weightInPool(uint256 index) public view returns (uint256) {
        LockedAsset memory asset = _lockedAssets[index];
        uint256 contractBalance = lockedAssetsBefore(_poolFees[_currentFeeIndex].depositDate);
        uint256 senderBalance = asset.amount;
        uint256 weightPercent = senderBalance.mul(10000).div(contractBalance).mul(100);
        return weightPercent;
    }

    function _deposit (address sender, uint256 amount, address referralAddr) internal {
        require(_token.balanceOf(sender) >= amount, "Transfer amount exceeds balance");
        require(
            _token.transferFrom(msg.sender, address(this), amount) == true,
            "Error transferFrom on the contract"
        );
        uint256 fee = amount * _fee / 10000;
        if(referralAddr != address(0) && referralAddr != msg.sender) {
            uint256 referralFee = fee * 5000 / 10000;
            uint256 baseFee = fee;
            fee = fee.sub(referralFee);
            require(
                _token.transfer(referralAddr, referralFee) == true,
                "Error transferFrom on the contract for referral"
            );
            emit ReferralReward(sender, referralAddr, amount, referralFee, baseFee);
        }
        uint256 depositFee = amount * _depositRewardFee / 10000;
        uint256 amountSubFee = amount.sub(fee).sub(depositFee);

        // Add fees to withdrawable amount by the owner
        _feesVault = _feesVault.add(fee);
        if(_poolFees[_currentFeeIndex].depositDate < block.timestamp) { // Create a new pool fee for today
            _currentFeeIndex++;
            _poolFees[_currentFeeIndex].amount = 0;
            _poolFees[_currentFeeIndex].depositDate = block.timestamp.add(1 days);
            emit NewPool(_currentFeeIndex, block.timestamp);
        }

        _poolFees[_currentFeeIndex].amount = _poolFees[_currentFeeIndex].amount.add(depositFee);

        // Set the balance
        _lockedAssets.push(LockedAsset({
            account: sender,
            fees: depositFee,
            baseAmount: amountSubFee,
            amount: amountSubFee,
            burnedHorn: 0,
            fromDate: block.timestamp,
            toDate: block.timestamp.add(_minLockDays * 1 days),
            referralAddr: referralAddr,
            alreadyClaimedHorn: 0,
            poolIndex: _currentFeeIndex,
            isBurnAsset: false,
            enterPoolFees: _poolFees[_currentFeeIndex].amount
        }));
        emit Deposit(sender, amount, fee.add(depositFee), block.timestamp, block.timestamp.add(_minLockDays * 1 days));
    }

    function withdraw() external payable override returns(bool) {
        require(!_isPaused, "Withdraw are paused for now");
        _withdraw(msg.sender);
        return true;
    }

    function _withdraw (address sender) internal {
        uint256 totalWithdraw = 0;

        if(_emergencyWithdraw) {
            for (uint256 i = 0; i < _lockedAssets.length; i++) {
                if(sender == _lockedAssets[i].account && _lockedAssets[i].amount > 0) {
                    totalWithdraw = totalWithdraw.add(_lockedAssets[i].amount);
                    _lockedAssets[i].amount = 0;
                }
            }
        }
        else {
            for (uint256 i = 0; i < _lockedAssets.length; i++) {
                if(sender == _lockedAssets[i].account && _lockedAssets[i].toDate <= block.timestamp && _lockedAssets[i].amount > 0) {
                    uint256 hornreward = 0;
                    if(!_lockedAssets[i].isBurnAsset) {
                        hornreward = _rewardWithdrawalHorn(sender, _lockedAssets[i].amount, _lockedAssets[i].fromDate, block.timestamp, _lockedAssets[i].alreadyClaimedHorn);
                    }
                    uint256 reward = _claimFeesForAsset(_lockedAssets[i], _lockedAssets[i].amount);
                    
                    if(!_lockedAssets[i].isBurnAsset) {
                        totalWithdraw = totalWithdraw.add(_lockedAssets[i].amount).add(reward);
                    } else {
                        totalWithdraw = totalWithdraw.add(reward);
                    }
                    _lockedAssets[i].alreadyClaimedHorn = _lockedAssets[i].alreadyClaimedHorn.add(hornreward);
                }
            }
            
            // Reset amount
            for (uint256 i = 0; i < _lockedAssets.length; i++) {
                if(sender == _lockedAssets[i].account && _lockedAssets[i].toDate <= block.timestamp && _lockedAssets[i].amount > 0) {
                    _lockedAssets[i].amount = 0;
                    _lockedAssets[i].burnedHorn = 0;
                }
            }
        }
        if(totalWithdraw <= 0) return;
        require(
            _token.transfer(sender, totalWithdraw) == true,
            "Error transferFrom on the contract"
        );
        emit Withdraw(sender, totalWithdraw);
    }

    function burn(uint256 amount) external payable override returns(bool) {
        require(!_isPaused, "Burn are paused for now");
        require(amount > 0, "Invalid amount");
        _burn(msg.sender, amount);
        return true;
    }

    function _burn (address sender, uint256 burnAmount) internal {
        require(_hornToken.balanceOf(sender) >= burnAmount, "Transfer amount exceeds balance");
        _hornToken.burn(sender, burnAmount);
        _lockedAssets.push(LockedAsset({
            account: sender,
            fees: 0,
            baseAmount: burnAmount.mul(_weightPerHorn).div(1 ether),
            amount: burnAmount.mul(_weightPerHorn).div(1 ether),
            burnedHorn: burnAmount,
            fromDate: block.timestamp,
            toDate: block.timestamp.add(_minLockDays * 1 days),
            referralAddr: address(0),
            alreadyClaimedHorn: 0,
            poolIndex: _currentFeeIndex,
            isBurnAsset: true,
            enterPoolFees: _poolFees[_currentFeeIndex].amount
        }));
        emit Burn(sender, burnAmount, burnAmount.mul(_weightPerHorn).div(1 ether));
    }

    function claimHorn() public payable {
        require(!_hornRewardDisabled, "Claim are disabled for now");
        uint256 totalClaim = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i += 1) {
            if(msg.sender == _lockedAssets[i].account && _lockedAssets[i].amount > 0 && !_lockedAssets[i].isBurnAsset) {
                uint256 reward = _rewardWithdrawalHorn(msg.sender, _lockedAssets[i].amount, _lockedAssets[i].fromDate, block.timestamp, _lockedAssets[i].alreadyClaimedHorn);
                _lockedAssets[i].alreadyClaimedHorn = _lockedAssets[i].alreadyClaimedHorn.add(reward);
                totalClaim = totalClaim.add(reward);
            }
        }
        if(totalClaim <= 0) return;
        emit Claim(msg.sender, totalClaim);
    }

    function _rewardWithdrawalHorn(address receiver, uint256 amount, uint256 fromDate, uint256 toDate, uint alreadyClaimed) internal returns (uint256) {
        if(_hornRewardDisabled) return 0;

        uint256 period = toDate.sub(fromDate).div(60).div(60).div(24);
        if(period <= 0) return 0;
        uint256 reward = _hornPerDay.mul(amount.mul(100)).div(10000).mul(period);
        reward = reward.div(100).sub(alreadyClaimed);
        if(reward <= 0) return 0;
        _hornToken.mint(address(this), reward);
        require(
            _hornToken.transfer(receiver, reward) == true,
            "Error transferFrom for reward on the contract"
        );
        return reward;
    }

    function _claimFeesForAsset(LockedAsset storage asset, uint withdrawAmount) internal returns (uint256) {
        uint256 totalReward = 0;
        for (uint256 y = 0; y < _currentFeeIndex + 1; y++) {
            if(_poolFees[y].amount > 0 && _poolFees[y].depositDate >= asset.fromDate) {
                uint256 contractBalance = lockedAssetsBefore(_poolFees[y].depositDate);
                if(asset.fees > _poolFees[y].amount) continue;
                uint256 fees = _poolFees[y].amount;
                if(y == asset.poolIndex) {
                    if(asset.enterPoolFees > 0 && fees >= asset.enterPoolFees) {
                        fees = fees.sub(asset.enterPoolFees);
                    }
                    else if(asset.enterPoolFees > 0 && fees < asset.enterPoolFees) {
                        continue;
                    }
                }
                uint256 senderBalance = withdrawAmount;
                uint256 weightPercent = senderBalance.mul(10000).div(contractBalance).mul(100);
                uint256 reward = fees * weightPercent / 1000000;
                totalReward = totalReward.add(reward);
                _poolFees[y].amount = _poolFees[y].amount.sub(reward);
            }
        }
        return totalReward;
    }

    function withdrawFees() public payable {
        require(msg.sender == _owner, "Only the owner can do this");
        require(
            _token.transfer(msg.sender, _feesVault) == true,
            "Error transferFrom on the contract"
        );
        _feesVault = 0;
        if(poolIsEmpty()) {
             require(
                _token.transfer(msg.sender, _token.balanceOf(address(this))) == true,
                "Error transferFrom on the contract"
            );
        }
    }

    function poolIsEmpty() public view returns (bool) {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _lockedAssets.length; i += 1) {
            totalAmount = totalAmount.add(_lockedAssets[i].amount);
        }
        return totalAmount == 0;
    }
}