pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {TripFund} from "../src/TripFund.sol";

contract DeployTripFund is Script {
    function run() external returns (address proxy) {
        address token = vm.envAddress("TOKEN_ADDRESS");
        address organizer = vm.envAddress("ORGANIZER");
        address adminOwner = vm.envAddress("PROXY_ADMIN_OWNER");
        uint256 goal = vm.envUint("GOAL");
        uint256 deadline = vm.envUint("DEADLINE");
        Options memory opts;
        opts.unsafeAllow = "constructor";

        vm.startBroadcast(msg.sender);
        proxy = Upgrades.deployTransparentProxy(
            "TripFund.sol:TripFund",
            adminOwner,
            abi.encodeCall(TripFund.initialize, (token, organizer, goal, deadline)),
            opts
        );
        vm.stopBroadcast();

        console2.log("Proxy", proxy);
        console2.log("Implementation", Upgrades.getImplementationAddress(proxy));
        console2.log("ProxyAdmin", Upgrades.getAdminAddress(proxy));
    }
}
