const hre = require("hardhat");
const { ethers, upgrades } = hre;

const deployBeacon = require("./deployBeacon.js");

module.exports = {
  deployFrabricERC20Beacon: async () => {
    return await deployBeacon([2], await ethers.getContractFactory("FrabricERC20"));
  },

  // Solely used for testing (as exported, used in this file for the intended to be used deployFRBC)
  deployFrabricERC20: async (beacon, args) => {
    process.hhCompiled ? null : await hre.run("compile");
    process.hhCompiled = true;

    const FrabricERC20 = await ethers.getContractFactory("FrabricERC20");

    const frbc = await upgrades.deployBeaconProxy(beacon, FrabricERC20, args);
    await frbc.deployed();
    return frbc;
  },

  deployFRBC: async (usdc, auction) => {
    let result = { beacon: await module.exports.deployFrabricERC20Beacon() };
    result.frbc = await module.exports.deployFrabricERC20(
      result.beacon,
      [
        "Frabric Token",
        "FRBC",
        // Supply is 0 as all distribution is via mint
        0,
        true,
        // Parent whitelist doesn't exist
        "0x0000000000000000000000000000000000000000",
        usdc,
        auction
      ]
    );
    return result;
  }
};

// These solely exist to test deployment scripts don't error when running,
// except for deployFrabric which actually will deploy the Frabric
if (require.main === module) {
  // Will disable the DEX functionality yet will deploy, which is all this block wants
  module.exports.deployFRBC("0x0000000000000000000000000000000000000000", "0x0000000000000000000000000000000000000000")
    .then(contracts => {
      console.log("FrabricERC20 Beacon: " + contracts.beacon.address);
      console.log("FRBC:                " + contracts.frbc.address);
    })
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
}
