pragma solidity 0.8.28;

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TripFund} from "../src/TripFund.sol";
import {DeployTripFund} from "../script/DeployTripFund.s.sol";
import {UpgradeTripFund} from "../script/UpgradeTripFund.s.sol";
import {TripFundBase} from "./TripFundBase.sol";

abstract contract TripFundScriptsBase is TripFundBase {
    function setUp() public override {
        adminOwner = address(this);
        super.setUp();
        vm.setEnv("TOKEN_ADDRESS", vm.toString(address(token)));
        vm.setEnv("ORGANIZER", vm.toString(organizer));
        vm.setEnv("PROXY_ADMIN_OWNER", vm.toString(adminOwner));
        vm.setEnv("GOAL", vm.toString(GOAL));
        vm.setEnv("DEADLINE", vm.toString(deadline));
    }
}

contract TripFundDeploymentScriptTest is TripFundScriptsBase {
    function test_DeploymentScriptInitializesProxy() public {
        address proxy = new DeployTripFund().run();
        assertGt(proxy.code.length, 0);
        TripFund deployed = TripFund(proxy);
        assertEq(address(deployed.token()), address(token));
        assertEq(deployed.organizer(), organizer);
        assertEq(deployed.goal(), GOAL);
        assertEq(deployed.deadline(), deadline);
        assertEq(ProxyAdmin(Upgrades.getAdminAddress(proxy)).owner(), adminOwner);
    }
}

contract TripFundUpgradeScriptTest is TripFundScriptsBase {
    function test_UpgradeScriptPreservesFund() public {
        _contribute(alice, UNIT);
        vm.setEnv("PROXY_ADDRESS", vm.toString(address(fund)));
        new UpgradeTripFund().run();
        assertTrue(Upgrades.getImplementationAddress(address(fund)) != implementation);
        assertEq(fund.totalRaised(), UNIT);
        assertEq(fund.contributions(alice), UNIT);
        assertEq(token.balanceOf(address(fund)), UNIT);
    }
}
