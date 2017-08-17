var SafeMath                  = artifacts.require("./imported/openzeppelin/SafeMath.sol");
var Wallet                    = artifacts.require("./imported/ethereum/Wallet.sol");
var MultisigLogic             = artifacts.require("./MultisigLogic.sol");
var ReservationFee            = artifacts.require("./ReservationFee.sol");

var Signatories               = require('fs').readFileSync("../../key/signatories.sig.test", 'utf-8').split('\n').filter(Boolean);
var RequiredSignatories       = 2;

module.exports = function(deployer, network, accounts)
{
  deployer.deploy(Wallet, Signatories, RequiredSignatories, 1 * Math.pow(10,18))
  .then(function() {
    return deployer.deploy(MultisigLogic, Signatories, RequiredSignatories);
  })
  .then(function() {
    return deployer.deploy(SafeMath);
  })
  .then(function() {
    return deployer.link(SafeMath, ReservationFee);
  })
  .then(function() {
    return deployer.deploy(ReservationFee, Wallet.address, MultisigLogic.address);
  })
  ;
};
