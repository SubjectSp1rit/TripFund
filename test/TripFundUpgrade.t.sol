pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Upgrades, Options} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundV2} from "../src/TripFundV2.sol";
import {TripFundBase} from "./TripFundBase.sol";

contract TripFundUpgradeTest is TripFundBase {
    function test_StorageLayoutIsCompatible() public {
        Upgrades.validateUpgrade("TripFundV2.sol:TripFundV2", _options(true));
    }

    function test_UpgradePreservesStateAndRefundsBeneficiary() public {
        address proxy = Upgrades.deployTransparentProxy(
            "TripFund.sol:TripFund",
            adminOwner,
            abi.encodeCall(TripFund.initialize, (address(token), organizer, GOAL, deadline)),
            _options(false)
        );
        fund = TripFund(proxy);
        address previousImplementation = Upgrades.getImplementationAddress(proxy);
        address previousAdmin = Upgrades.getAdminAddress(proxy);
        assertEq(ProxyAdmin(previousAdmin).owner(), adminOwner);
        _contribute(alice, 200 * UNIT);
        _contribute(bob, 300 * UNIT);
        vm.prank(alice);
        token.approve(proxy, 500 * UNIT);

        _upgrade();

        assertEq(address(fund), proxy);
        assertTrue(Upgrades.getImplementationAddress(proxy) != previousImplementation);
        assertEq(Upgrades.getAdminAddress(proxy), previousAdmin);
        assertEq(ProxyAdmin(previousAdmin).owner(), adminOwner);
        _assertParameters();
        assertEq(fund.contributions(alice), 200 * UNIT);
        assertEq(fund.contributions(bob), 300 * UNIT);
        assertEq(fund.totalRaised(), 500 * UNIT);
        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(proxy), 500 * UNIT);
        assertEq(token.allowance(alice, proxy), 500 * UNIT);

        vm.prank(alice);
        TripFundV2(proxy).contributeFor(carol, 100 * UNIT);
        _contribute(bob, 50 * UNIT);
        assertEq(fund.contributions(alice), 200 * UNIT);
        assertEq(fund.contributions(bob), 350 * UNIT);
        assertEq(fund.contributions(carol), 100 * UNIT);
        assertEq(fund.totalRaised(), 650 * UNIT);
        assertEq(token.balanceOf(proxy), 650 * UNIT);
        assertEq(token.allowance(alice, proxy), 400 * UNIT);

        vm.warp(deadline);
        _refund(alice);
        _refund(bob);
        _refund(carol);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 100 * UNIT);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
        assertEq(token.balanceOf(carol), INITIAL_BALANCE + 100 * UNIT);
        assertEq(token.balanceOf(proxy), 0);
        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(bob), 0);
        assertEq(fund.contributions(carol), 0);
        assertEq(fund.totalRaised(), 650 * UNIT);
    }

    function test_OnlyProxyAdminOwnerCanUpgrade() public {
        address next = Upgrades.prepareUpgrade("TripFundV2.sol:TripFundV2", _options(true));
        address proxy = address(fund);
        address admin = Upgrades.getAdminAddress(proxy);
        assertEq(ProxyAdmin(admin).owner(), adminOwner);
        address[3] memory unauthorized = [alice, organizer, bob];
        for (uint256 i; i < unauthorized.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized[i])
            );
            vm.prank(unauthorized[i]);
            ProxyAdmin(admin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), next, "");
            assertEq(Upgrades.getImplementationAddress(proxy), implementation);
        }
        vm.prank(adminOwner);
        ProxyAdmin(admin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), next, "");
        assertEq(Upgrades.getImplementationAddress(proxy), next);
    }

    function test_RejectReinitializationAfterUpgrade() public {
        address first = implementation;
        _upgrade();
        address second = Upgrades.getImplementationAddress(address(fund));
        address[3] memory targets = [address(fund), first, second];
        for (uint256 i; i < targets.length; ++i) {
            vm.expectRevert(Initializable.InvalidInitialization.selector);
            vm.prank(alice);
            TripFund(targets[i]).initialize(address(token), alice, 1, deadline + 1);
        }
        _assertParameters();
    }

    function test_WithdrawAfterUpgradeKeepsDirectTransfers() public {
        _contribute(alice, GOAL - UNIT);
        _donate(200 * UNIT);
        _upgrade();
        _contribute(bob, UNIT);
        vm.warp(deadline);
        vm.expectRevert(TripFund.GoalReached.selector);
        vm.prank(alice);
        fund.refund();
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 200 * UNIT);
        assertEq(fund.totalRaised(), GOAL);
        assertTrue(fund.withdrawn());
        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        vm.prank(organizer);
        fund.withdraw();
    }

    function test_DeadlineStillAppliesAfterUpgrade() public {
        _upgrade();
        vm.warp(deadline);
        _expectContributionFailure(
            alice, UNIT, abi.encodeWithSelector(TripFund.DeadlineReached.selector)
        );
        vm.expectRevert(TripFund.DeadlineReached.selector);
        vm.prank(alice);
        TripFundV2(address(fund)).contributeFor(carol, UNIT);
        assertEq(fund.totalRaised(), 0);
        assertEq(fund.contributions(carol), 0);
    }

    function test_ContributionForUnavailableBeforeUpgrade() public {
        vm.expectRevert(bytes(""));
        vm.prank(alice);
        TripFundV2(address(fund)).contributeFor(carol, UNIT);
    }

    function _upgrade() private {
        assertLt(block.timestamp, deadline);
        Upgrades.upgradeProxy(
            address(fund), "TripFundV2.sol:TripFundV2", "", _options(true), adminOwner
        );
    }

    function _options(bool referenceV1) private pure returns (Options memory opts) {
        opts.unsafeAllow = "constructor";
        if (referenceV1) opts.referenceContract = "TripFund.sol:TripFund";
    }

    function _assertParameters() private view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
    }
}
