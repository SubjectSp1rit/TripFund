pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";

contract UpgradeTripFund is Script {
    function run() external {
        address proxy = vm.envAddress("PROXY_ADDRESS");
        Options memory opts;
        opts.unsafeAllow = "constructor";
        opts.referenceContract = "TripFund.sol:TripFund";

        vm.startBroadcast(msg.sender);
        Upgrades.upgradeProxy(proxy, "TripFundV2.sol:TripFundV2", "", opts);
        vm.stopBroadcast();

        console2.log("Proxy", proxy);
        console2.log("Implementation", Upgrades.getImplementationAddress(proxy));
    }
}
