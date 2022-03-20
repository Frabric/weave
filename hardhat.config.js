require("@nomiclabs/hardhat-waffle");
require("@openzeppelin/hardhat-upgrades");
require("solidity-coverage");

module.exports = {
  solidity: {
    version: "0.8.9",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  }
};
