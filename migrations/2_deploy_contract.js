var HornToken = artifacts.require("HornToken");
var HornLockVault_Horn = artifacts.require("HornLockVault");
var HornTokenABI = require('../build/contracts/HornToken.json');

module.exports = async function(deployer) {
  /**
  await deployer.deploy(HornToken);
  const _tokenInstance = await HornToken.deployed();
  
  await deployer.deploy(HornLockVault_Horn, _tokenInstance.address, _tokenInstance.address, 20, 10, "100", "10");
  await HornLockVault_Horn.deployed();
 */

  //await deployer.deploy(HornToken);
  //const _tokenInstance = await HornToken.deployed();
  
  // Ropsten
  // Horn Vault
  await deployer.deploy(HornLockVault_Horn, "0x0850e38e4ec34d1d83130ab47a57a955158a7f36", "0x0850e38e4ec34d1d83130ab47a57a955158a7f36", 20, 
    10, "10000", 0, "1000000000000000000");
  // PTE Vault
  //await deployer.deploy(HornLockVault_Horn, "0x2158146e3012f671e4e3eee72611224027c3fcfd", "0x0850e38e4ec34d1d83130ab47a57a955158a7f36", 50, 
  //  200, "150000", 1, "20000000000000000");
  
  const tokenInstance = new web3.eth.Contract(HornTokenABI.abi, "0x0850e38e4ec34d1d83130ab47a57a955158a7f36");
  
  //await deployer.deploy(HornLockVault_Horn, "0xc778417e063141139fce010982780140aa0cd5ab", "0x0850e38e4ec34d1d83130ab47a57a955158a7f36", 50, 50, "1500", "10", 1);
  // Dev
  //await deployer.deploy(HornLockVault_Horn, "0x901727dF7F255100aa7cF73b160085f5843c373C", "0x901727dF7F255100aa7cF73b160085f5843c373C", 20, 10, "100", 0,
  //   "1000000000000000000");
  //const tokenInstance = new web3.eth.Contract(HornTokenABI.abi, "0x901727dF7F255100aa7cF73b160085f5843c373C");

  const accounts = await web3.eth.getAccounts();
  const vaultInstance = await HornLockVault_Horn.deployed();
  const minterRole = await tokenInstance.methods.MINTER_ROLE().call();
  const burnerRole = await tokenInstance.methods.BURNER_ROLE().call();
  await tokenInstance.methods.grantRole(minterRole, vaultInstance.address).send({ from: accounts[0] });
  await tokenInstance.methods.grantRole(burnerRole, vaultInstance.address).send({ from: accounts[0] });
};
