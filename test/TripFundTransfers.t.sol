pragma solidity 0.8.28;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TripFundBase} from "./TripFundBase.sol";
import {FailingERC20} from "./mocks/FailingERC20.sol";

contract TripFundTransfersTest is TripFundBase {
    FailingERC20 private failing;

    function setUp() public override {
        super.setUp();
        failing = new FailingERC20();
        token = failing;
        _mintParticipants();
        fund = _deployFund(implementation, address(token), organizer, GOAL, deadline);
    }

    function test_ContributionRollsBackOnTokenRevert() public {
        _checkContributionFailure(FailingERC20.Failure.Revert);
    }

    function test_ContributionRollsBackOnFalseReturn() public {
        _checkContributionFailure(FailingERC20.Failure.ReturnFalse);
    }

    function test_WithdrawalRollsBackOnTokenRevert() public {
        _checkWithdrawalFailure(FailingERC20.Failure.Revert);
    }

    function test_WithdrawalRollsBackOnFalseReturn() public {
        _checkWithdrawalFailure(FailingERC20.Failure.ReturnFalse);
    }

    function test_RefundRollsBackOnTokenRevert() public {
        _checkRefundFailure(FailingERC20.Failure.Revert);
    }

    function test_RefundRollsBackOnFalseReturn() public {
        _checkRefundFailure(FailingERC20.Failure.ReturnFalse);
    }

    function _checkContributionFailure(FailingERC20.Failure mode) private {
        _contribute(alice, 100 * UNIT);
        vm.prank(alice);
        token.approve(address(fund), UNIT);
        failing.setTransferFromFailure(mode);
        _expectContributionFailure(alice, UNIT, _reason(mode));
        failing.setTransferFromFailure(FailingERC20.Failure.None);
        vm.prank(alice);
        fund.contribute(UNIT);
        assertEq(fund.contributions(alice), 101 * UNIT);
        assertEq(fund.totalRaised(), 101 * UNIT);
    }

    function _checkWithdrawalFailure(FailingERC20.Failure mode) private {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        failing.setTransferFailure(mode);
        bytes memory reason = _reason(mode);
        vm.expectRevert(reason);
        vm.prank(organizer);
        fund.withdraw();
        assertFalse(fund.withdrawn());
        assertEq(fund.totalRaised(), GOAL);
        assertEq(fund.contributions(alice), GOAL);
        assertEq(token.balanceOf(address(fund)), GOAL);
        assertEq(token.balanceOf(organizer), 0);
        failing.setTransferFailure(FailingERC20.Failure.None);
        vm.prank(organizer);
        fund.withdraw();
        assertTrue(fund.withdrawn());
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function _checkRefundFailure(FailingERC20.Failure mode) private {
        _contribute(alice, UNIT);
        vm.warp(deadline);
        failing.setTransferFailure(mode);
        bytes memory reason = _reason(mode);
        vm.expectRevert(reason);
        vm.prank(alice);
        fund.refund();
        assertEq(fund.contributions(alice), UNIT);
        assertEq(fund.totalRaised(), UNIT);
        assertEq(token.balanceOf(address(fund)), UNIT);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - UNIT);
        failing.setTransferFailure(FailingERC20.Failure.None);
        _refund(alice);
        assertEq(fund.contributions(alice), 0);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
    }

    function _reason(FailingERC20.Failure mode) private view returns (bytes memory) {
        if (mode == FailingERC20.Failure.Revert) {
            return abi.encodeWithSelector(FailingERC20.TransferFailed.selector);
        }
        return abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token));
    }
}
