pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TripFund} from "../src/TripFund.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

abstract contract TripFundBase is Test {
    uint256 internal constant UNIT = 1e6;
    uint256 internal constant GOAL = 1_000 * UNIT;
    uint256 internal constant INITIAL_BALANCE = 10_000 * UNIT;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal organizer = makeAddr("organizer");
    address internal adminOwner = makeAddr("adminOwner");
    MockERC20 internal token;
    TripFund internal fund;
    address internal implementation;
    uint256 internal deadline;

    function setUp() public virtual {
        vm.warp(1_000_000);
        deadline = block.timestamp + 1 hours;
        token = new MockERC20();
        _mintParticipants();
        implementation = address(new TripFund());
        fund = _deployFund(implementation, address(token), organizer, GOAL, deadline);
    }

    function _deployFund(
        address logic,
        address asset,
        address recipient,
        uint256 target,
        uint256 end
    ) internal returns (TripFund) {
        return TripFund(
            address(
                new TransparentUpgradeableProxy(
                    logic,
                    adminOwner,
                    abi.encodeCall(TripFund.initialize, (asset, recipient, target, end))
                )
            )
        );
    }

    function _mintParticipants() internal {
        token.mint(alice, INITIAL_BALANCE);
        token.mint(bob, INITIAL_BALANCE);
        token.mint(carol, INITIAL_BALANCE);
    }

    function _contribute(address contributor, uint256 amount) internal {
        vm.startPrank(contributor);
        token.approve(address(fund), amount);
        fund.contribute(amount);
        vm.stopPrank();
    }

    function _donate(uint256 amount) internal {
        vm.prank(carol);
        assertTrue(token.transfer(address(fund), amount));
    }

    function _refund(address contributor) internal {
        vm.prank(contributor);
        fund.refund();
    }

    function _expectContributionFailure(address contributor, uint256 amount, bytes memory reason)
        internal
    {
        uint256 contribution = fund.contributions(contributor);
        uint256 raised = fund.totalRaised();
        uint256 fundBalance = token.balanceOf(address(fund));
        uint256 userBalance = token.balanceOf(contributor);
        uint256 allowance = token.allowance(contributor, address(fund));
        vm.expectRevert(reason);
        vm.prank(contributor);
        fund.contribute(amount);
        assertEq(fund.contributions(contributor), contribution);
        assertEq(fund.totalRaised(), raised);
        assertEq(token.balanceOf(address(fund)), fundBalance);
        assertEq(token.balanceOf(contributor), userBalance);
        assertEq(token.allowance(contributor, address(fund)), allowance);
    }
}
