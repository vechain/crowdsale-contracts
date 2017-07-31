var VEN = artifacts.require("./Ven.sol");
var VENSale = artifacts.require("./VenSale.sol");

module.exports = function(deployer) {
  deployer.deploy(VEN);
  deployer.deploy(VENSale);
};
