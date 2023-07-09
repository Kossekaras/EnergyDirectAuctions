const EnergyAuction = artifacts.require("EnergyAuction");

module.exports = function(deployer) {
  deployer.deploy(EnergyAuction);
};
