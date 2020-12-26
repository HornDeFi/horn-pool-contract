const HornToken = artifacts.require("HornToken");
const HornLockVault = artifacts.require("HornLockVault");
const BN = web3.utils.BN;
const moment = require('moment'); 

contract("HornToken", async accounts => {
    var vaultInstance;
    var tokenInstance;

    before(async() => {
        tokenInstance = await HornToken.deployed();
        vaultInstance = await HornLockVault.deployed();
    })

    it("add the vault to the minter roles", async () => {
        const minterRole = await tokenInstance.MINTER_ROLE();
        const burnerRole = await tokenInstance.BURNER_ROLE();
        await tokenInstance.grantRole(minterRole, vaultInstance.address, { from: accounts[0] });
        await tokenInstance.grantRole(burnerRole, vaultInstance.address, { from: accounts[0] });
    })

    it("deposit 100 HORN token in the vault", async () => {
        const initialBalance = await tokenInstance.balanceOf.call(accounts[0]);
        await tokenInstance.approve(vaultInstance.address, "20000000000000000000000", { from: accounts[0] })
        await vaultInstance.deposit("100000000000000000000", "0x0000000000000000000000000000000000000000");
        await vaultInstance.deposit("100000000000000000000", "0x0000000000000000000000000000000000000000");
        console.log(await vaultInstance.claimableFees.call(accounts[0], 1))
        const balance = await tokenInstance.balanceOf.call(accounts[0]);
        assert.equal(
            initialBalance.sub(balance).toString(),
            "200000000000000000000",
            "should have 10 HORN removed"
        );
    })

    it("should have locked assets", async () => {
        const reserve = await vaultInstance.lockedAssets();
        assert.equal(
            reserve.toString(),
            "199400000000000000000",
            "should have 19.94 HORN in reserve"
        );
    })
    
    it("withdraw 5 HORN token from the vault", async () => {
        const initialBalance = await tokenInstance.balanceOf.call(accounts[0]);
        await vaultInstance.withdraw();
        const balance = await tokenInstance.balanceOf.call(accounts[0]);
        console.log((await vaultInstance.lockedAssets()).toString())

    })
});