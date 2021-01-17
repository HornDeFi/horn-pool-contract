// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.7.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./interfaces/IHornLockVault.sol";
import "./interfaces/IExtendedERC20.sol";

contract HornLockVaultV2 is IHornLockVault {
    using SafeMath for uint256;

    struct LockedAsset {
        address account;
        uint256 amount;
        uint256 burnedHorn;
        uint256 fees;
        uint256 fromDate;
        uint256 toDate;
        uint256 alreadyClaimedHorn;
        bool isBurnAsset;
        uint256 depositIndex;
        uint256 enterPoolFees;
    }

    struct RewardFee {
        uint256 totalAssetAmount;
        uint256 totalFeesAmount;
        uint256 amount;
        uint256 depositIndex;
    }

    mapping(address => LockedAsset[]) private _lockedAssetsByAddress;
    mapping(uint256 => uint256) private _feesAtIndex;
    RewardFee private _poolFees;

    bool public _isActive = true;
    address public _createdFrom;
    address public _owner;
    string public _vaultName;
    uint128 public _fee;
    uint128 public _depositRewardFee;
    uint256 public _hornPerDay;
    uint256 public _feesVault;
    uint256 public _minLockDays;
    uint256 public _weightPerHorn;
    uint256 private _depositIndex = 0;
    bool public _isPaused = false;
    bool public _hornRewardDisabled = false;
    IExtendedERC20 private _token;
    address public _tokenAddr;
    IExtendedERC20 private _hornToken;
    address public _hornTokenAddr;

    constructor(
        address owner,
        address lockedTokenAddr,
        address hornTokenAddr,
        uint128 fee,
        uint128 depositRewardFee,
        uint256 hornPerDay,
        uint256 minLockDays,
        uint256 weightPerHorn
    ) {
        _createdFrom = msg.sender;
        _owner = owner;
        _tokenAddr = lockedTokenAddr;
        _token = IExtendedERC20(lockedTokenAddr);
        _hornTokenAddr = hornTokenAddr;
        _hornToken = IExtendedERC20(hornTokenAddr);
        _vaultName = _token.symbol();
        _fee = fee;
        _depositRewardFee = depositRewardFee;
        _hornPerDay = hornPerDay;
        _minLockDays = minLockDays;
        _weightPerHorn = weightPerHorn;

        _poolFees = RewardFee({
            amount: 0,
            totalFeesAmount: 0,
            totalAssetAmount: 0,
            depositIndex: _depositIndex
        });
    }

    function balanceOf(address account) public view override returns (uint256) {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssetsByAddress[account].length; i++) {
            if (_lockedAssetsByAddress[account][i].isBurnAsset || _lockedAssetsByAddress[account][i].amount <= 0) continue;
            totalBalance = totalBalance.add(
                _lockedAssetsByAddress[account][i].amount
            );
        }
        return totalBalance;
    }

    function claimableBalanceOf(address account)
        public
        view
        override
        returns (uint256)
    {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssetsByAddress[account].length; i++) {
            if (_lockedAssetsByAddress[account][i].isBurnAsset) continue;
            if (_lockedAssetsByAddress[account][i].toDate <= block.timestamp) {
                totalBalance = totalBalance.add(
                    _lockedAssetsByAddress[account][i].amount
                );
            }
        }
        return totalBalance;
    }

    function claimableHornOf(address account)
        public
        view
        override
        returns (uint256)
    {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssetsByAddress[account].length; i++) {
            if (
                _lockedAssetsByAddress[account][i].amount > 0 &&
                !_lockedAssetsByAddress[account][i].isBurnAsset
            ) {
                LockedAsset memory asset = _lockedAssetsByAddress[account][i];
                uint256 period =
                    block.timestamp.sub(asset.fromDate).div(60).div(60).div(24);
                if (period <= 0) continue;
                uint256 reward =
                    _hornPerDay.mul(asset.amount.mul(100)).div(10000).mul(
                        period
                    );
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
        uint256 totalBalance = _token.balanceOf(address(this)).sub(_feesVault);
        return totalBalance;
    }

    function getBurnedHornAmount(address account)
        public
        view
        returns (uint256)
    {
        uint256 totalBalance = 0;
        for (uint256 i = 0; i < _lockedAssetsByAddress[account].length; i++) {
            if (
                account == _lockedAssetsByAddress[account][i].account &&
                _lockedAssetsByAddress[account][i].isBurnAsset
            ) {
                totalBalance = totalBalance.add(
                    _lockedAssetsByAddress[account][i].burnedHorn
                );
            }
        }
        return totalBalance;
    }

    function name() public view returns (string memory) {
        return _vaultName;
    }

    function setPauseState(bool newState) external payable returns (bool) {
        require(
            msg.sender == _owner || msg.sender == _createdFrom,
            "Only the owner can do this"
        );
        _isPaused = newState;
        return true;
    }

    function setActiveState(bool newState) external payable returns (bool) {
        require(
            msg.sender == _owner || msg.sender == _createdFrom,
            "Only the owner can do this"
        );
        _isActive = newState;
        return true;
    }

    function setHornRewardDisabledState(bool newState)
        external
        payable
        returns (bool)
    {
        require(
            msg.sender == _owner || msg.sender == _createdFrom,
            "Only the owner can do this"
        );
        _hornRewardDisabled = newState;
        return true;
    }

    function deposit(uint256 amount, address referralAddr)
        external
        payable
        override
        returns (bool)
    {
        require(amount > 0, "Invalid amount");
        require(!_isPaused, "Deposit are paused for now");
        _deposit(msg.sender, amount, referralAddr);
        return true;
    }

    function balanceIndexes(address account, bool filterBurned)
        public
        view
        returns (uint256[] memory)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < _lockedAssetsByAddress[account].length; i++) {
            if (
                _lockedAssetsByAddress[account][i].amount > 0 &&
                _lockedAssetsByAddress[account][i].isBurnAsset == filterBurned
            ) {
                count++;
            }
        }
        uint256[] memory indexes = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < _lockedAssetsByAddress[account].length; i++) {
            if (
                _lockedAssetsByAddress[account][i].amount > 0 &&
                _lockedAssetsByAddress[account][i].isBurnAsset == filterBurned
            ) {
                indexes[index] = i;
                index++;
            }
        }
        return indexes;
    }

    function getLockedAssetsCountByAccount(address account)
        public
        view
        returns (uint256)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < _lockedAssetsByAddress[account].length; i++) {
            if (
                _lockedAssetsByAddress[account][i].account == account &&
                _lockedAssetsByAddress[account][i].amount > 0
            ) {
                count++;
            }
        }
        return count;
    }

    function claimableFees(address account, uint256 index)
        public
        view
        returns (uint256)
    {
        uint256 totalFees = 0;
        LockedAsset memory asset = _lockedAssetsByAddress[account][index];
        if (
            _poolFees.amount <= 0 ||
            asset.fees > _poolFees.amount ||
            asset.account != account ||
            asset.amount <= 0
        ) return 0;

        uint256 contractBalance = _poolFees.totalAssetAmount;
        if (asset.fees > _poolFees.amount) return 0;
        uint256 feesSinceDeposit =
            _feesAtIndex[_depositIndex].sub(_feesAtIndex[asset.depositIndex]); // gas saver
        uint256 reducedEnterPoolFees = asset.enterPoolFees;
        if (feesSinceDeposit > reducedEnterPoolFees) {
            reducedEnterPoolFees = 0;
        } else {
            reducedEnterPoolFees = reducedEnterPoolFees.sub(feesSinceDeposit);
        }
        
        uint256 fees = 0;
        if(_poolFees.amount >= reducedEnterPoolFees) {
            fees = _poolFees.amount.sub(reducedEnterPoolFees);
        }
        else {
            fees = _poolFees.amount;
        }


        uint256 senderBalance = asset.amount;
        uint256 weightPercent =
            senderBalance.mul(10000).div(contractBalance).mul(100);
        uint256 reward = fees.mul(weightPercent).div(1000000);
        totalFees = totalFees.add(reward);
        return totalFees;
    }

    function weightInPool(address account, uint256 index)
        public
        view
        returns (uint256)
    {
        LockedAsset memory asset = _lockedAssetsByAddress[account][index];
        uint256 contractBalance = _poolFees.totalAssetAmount;
        uint256 senderBalance = asset.amount;
        uint256 weightPercent =
            senderBalance.mul(10000).div(contractBalance).mul(100);
        return weightPercent;
    }

    function _deposit(
        address sender,
        uint256 amount,
        address referralAddr
    ) internal {
        require(
            _token.balanceOf(sender) >= amount,
            "Transfer amount exceeds balance"
        );
        require(
            _token.transferFrom(msg.sender, address(this), amount) == true,
            "Error transferFrom on the contract"
        );
        uint256 fee = (amount * _fee) / 10000;
        if (referralAddr != address(0) && referralAddr != msg.sender) {
            uint256 referralFee = (fee * 5000) / 10000;
            uint256 baseFee = fee;
            fee = fee.sub(referralFee);
            require(
                _token.transfer(referralAddr, referralFee) == true,
                "Error transferFrom on the contract for referral"
            );
            emit ReferralReward(
                sender,
                referralAddr,
                amount,
                referralFee,
                baseFee
            );
        }
        uint256 depositFee = (amount * _depositRewardFee) / 10000;
        uint256 amountSubFee = amount.sub(fee).sub(depositFee);

        // Add fees to withdrawable amount by the owner
        _feesVault = _feesVault.add(fee);
        if (_depositIndex == 0) {
            // If is the first deposit all fees goes the vault
            _feesVault = _feesVault.add(depositFee);
        } else {
            _poolFees.totalFeesAmount = _poolFees.totalFeesAmount.add(
                depositFee
            );
            _poolFees.amount = _poolFees.amount.add(depositFee);
        }
        _poolFees.totalAssetAmount = _poolFees.totalAssetAmount.add(
            amountSubFee
        );

        _depositIndex = _depositIndex.add(1);
        _poolFees.depositIndex = _depositIndex;
        _feesAtIndex[_depositIndex] = _poolFees.totalFeesAmount;

        _lockedAssetsByAddress[sender].push(
            LockedAsset({
                enterPoolFees: _poolFees.amount,
                account: sender,
                fees: depositFee,
                amount: amountSubFee,
                burnedHorn: 0,
                fromDate: block.timestamp,
                toDate: block.timestamp.add(_minLockDays * 1 days),
                alreadyClaimedHorn: 0,
                isBurnAsset: false,
                depositIndex: _depositIndex
            })
        );

        emit Deposit(
            sender,
            amount,
            fee.add(depositFee),
            block.timestamp,
            block.timestamp.add(_minLockDays * 1 days)
        );
    }

    function withdraw() external payable override returns (bool) {
        require(!_isPaused, "Withdraw are paused for now");
        _withdraw(msg.sender);
        return true;
    }

    function _withdraw(address sender) internal {
        uint256 totalWithdraw = 0;
        uint256 totalRemovedAssetsCount = 0;
        for (uint256 i = 0; i < _lockedAssetsByAddress[sender].length; i++) {
            LockedAsset storage asset = _lockedAssetsByAddress[sender][i];
            if (asset.toDate <= block.timestamp && asset.amount > 0) {
                totalRemovedAssetsCount = totalRemovedAssetsCount + 1;
                uint256 hornreward = 0;
                if (!asset.isBurnAsset) {
                    hornreward = _rewardWithdrawalHorn(
                        sender,
                        asset.amount,
                        asset.fromDate,
                        block.timestamp,
                        asset.alreadyClaimedHorn
                    );
                }
                uint256 reward = _claimFeesForAsset(asset, asset.amount);

                if (!asset.isBurnAsset) {
                    totalWithdraw = totalWithdraw.add(asset.amount).add(reward);
                } else {
                    totalWithdraw = totalWithdraw.add(reward);
                }
                asset.alreadyClaimedHorn = asset.alreadyClaimedHorn.add(
                    hornreward
                );
            }
        }

        // Reset amount
        LockedAsset[] storage newLockedAssetArray;
        for (uint256 i = 0; i < _lockedAssetsByAddress[sender].length; i++) {
            LockedAsset storage asset = _lockedAssetsByAddress[sender][i];
            if (asset.toDate <= block.timestamp && asset.amount > 0) {
                asset.amount = 0;
                asset.burnedHorn = 0;
            } else {
                newLockedAssetArray.push(_lockedAssetsByAddress[sender][i]);
            }
        }
        _lockedAssetsByAddress[sender] = newLockedAssetArray;

        if (totalWithdraw <= 0) return;
        require(
            _token.transfer(sender, totalWithdraw) == true,
            "Error transferFrom on the contract"
        );
        emit Withdraw(sender, totalWithdraw);
    }

    function burn(uint256 amount) external payable override returns (bool) {
        require(!_isPaused, "Burn are paused for now");
        require(amount > 0, "Invalid amount");
        _burn(msg.sender, amount);
        return true;
    }

    function _burn(address sender, uint256 burnAmount) internal {
        require(
            _hornToken.balanceOf(sender) >= burnAmount,
            "Transfer amount exceeds balance"
        );
        _hornToken.burn(sender, burnAmount);

        _depositIndex = _depositIndex.add(1);
        _lockedAssetsByAddress[sender].push(
            LockedAsset({
                enterPoolFees: _poolFees.amount,
                account: sender,
                fees: 0,
                amount: burnAmount.mul(_weightPerHorn).div(1 ether),
                burnedHorn: burnAmount,
                fromDate: block.timestamp,
                toDate: block.timestamp.add(_minLockDays * 1 days),
                alreadyClaimedHorn: 0,
                isBurnAsset: true,
                depositIndex: _depositIndex
            })
        );
        emit Burn(
            sender,
            burnAmount,
            burnAmount.mul(_weightPerHorn).div(1 ether)
        );
    }

    function claimHorn() public payable {
        require(!_hornRewardDisabled, "Claim are disabled for now");
        uint256 totalClaim = 0;
        for (
            uint256 i = 0;
            i < _lockedAssetsByAddress[msg.sender].length;
            i += 1
        ) {
            LockedAsset storage asset = _lockedAssetsByAddress[msg.sender][i];
            if (asset.amount > 0 && !asset.isBurnAsset) {
                uint256 reward =
                    _rewardWithdrawalHorn(
                        msg.sender,
                        asset.amount,
                        asset.fromDate,
                        block.timestamp,
                        asset.alreadyClaimedHorn
                    );
                asset.alreadyClaimedHorn = asset.alreadyClaimedHorn.add(reward);
                totalClaim = totalClaim.add(reward);
            }
        }
        if (totalClaim <= 0) return;
        emit Claim(msg.sender, totalClaim);
    }

    function _rewardWithdrawalHorn(
        address receiver,
        uint256 amount,
        uint256 fromDate,
        uint256 toDate,
        uint256 alreadyClaimed
    ) internal returns (uint256) {
        if (_hornRewardDisabled) return 0;

        uint256 period = toDate.sub(fromDate).div(60).div(60).div(24);
        if (period <= 0) return 0;
        uint256 reward =
            _hornPerDay.mul(amount.mul(100)).div(10000).mul(period);
        reward = reward.div(100).sub(alreadyClaimed);
        if (reward <= 0) return 0;
        _hornToken.mint(address(this), reward);
        require(
            _hornToken.transfer(receiver, reward) == true,
            "Error transferFrom for reward on the contract"
        );
        return reward;
    }

    function _claimFeesForAsset(
        LockedAsset storage asset,
        uint256 withdrawAmount
    ) internal returns (uint256) {
        if (_poolFees.amount <= 0 || asset.fees > _poolFees.amount) return 0;
        uint256 contractBalance = _poolFees.totalAssetAmount;
        uint256 feesSinceDeposit =
            _feesAtIndex[_depositIndex].sub(_feesAtIndex[asset.depositIndex]); // gas saver
        uint256 reducedEnterPoolFees = asset.enterPoolFees;
        if (feesSinceDeposit > reducedEnterPoolFees) {
            reducedEnterPoolFees = 0;
        } else {
            reducedEnterPoolFees = reducedEnterPoolFees.sub(feesSinceDeposit);
        }

        uint256 fees = 0;
        if(_poolFees.amount >= reducedEnterPoolFees) {
            fees = _poolFees.amount.sub(reducedEnterPoolFees);
        }
        else {
            fees = _poolFees.amount;
        }

        uint256 senderBalance = withdrawAmount;
        uint256 reward = (fees * (senderBalance.mul(10000).div(contractBalance).mul(100))) / 1000000;

        _poolFees.amount = _poolFees.amount.sub(reward);
        _poolFees.totalAssetAmount = _poolFees.totalAssetAmount.sub(
            withdrawAmount
        );
        return reward;
    }

    function withdrawFees() public payable {
        require(
            msg.sender == _owner || msg.sender == _createdFrom,
            "Only the owner can do this"
        );
        require(
            _token.transfer(msg.sender, _feesVault) == true,
            "Error transferFrom on the contract"
        );
        _feesVault = 0;
    }
}
