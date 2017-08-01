var VEN = artifacts.require("./VEN.sol");
var VENSale = artifacts.require("./VENSale.sol");

module.exports = function(deployer) {
  deployer.deploy(VEN);
  deployer.deploy(VENSale);
};
