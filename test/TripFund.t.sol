pragma solidity 0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundBase} from "./TripFundBase.sol";

contract TripFundTest is TripFundBase {
    event Contributed(address indexed contributor, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);
    event Withdrawn(address indexed organizer, uint256 amount);

    function test_Initialization() public view {
        assertEq(address(fund.token()), address(token));
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
        assertEq(fund.totalRaised(), 0);
        assertEq(fund.contributions(alice), 0);
        assertFalse(fund.withdrawn());
        assertEq(token.decimals(), 6);
    }

    function test_RejectZeroToken() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        _deployFund(implementation, address(0), organizer, GOAL, deadline);
    }

    function test_RejectZeroOrganizer() public {
        vm.expectRevert(TripFund.ZeroAddress.selector);
        _deployFund(implementation, address(token), address(0), GOAL, deadline);
    }

    function test_RejectZeroGoal() public {
        vm.expectRevert(TripFund.ZeroGoal.selector);
        _deployFund(implementation, address(token), organizer, 0, deadline);
    }

    function test_RejectPastDeadline() public {
        uint256 end = block.timestamp - 1;
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        _deployFund(implementation, address(token), organizer, GOAL, end);
    }

    function test_RejectCurrentDeadline() public {
        uint256 end = block.timestamp;
        vm.expectRevert(TripFund.InvalidDeadline.selector);
        _deployFund(implementation, address(token), organizer, GOAL, end);
    }

    function test_RejectRepeatedInitialization() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vm.prank(alice);
        fund.initialize(address(token), alice, 1, deadline + 1);
        assertEq(fund.organizer(), organizer);
        assertEq(fund.goal(), GOAL);
        assertEq(fund.deadline(), deadline);
    }

    function test_ImplementationCannotBeInitialized() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        TripFund(implementation).initialize(address(token), organizer, GOAL, deadline);
    }

    function test_ContributionsAccumulate() public {
        _contribute(alice, 200 * UNIT);
        _contribute(alice, 150 * UNIT);
        _contribute(bob, 250 * UNIT);
        assertEq(fund.contributions(alice), 350 * UNIT);
        assertEq(fund.contributions(bob), 250 * UNIT);
        assertEq(fund.totalRaised(), 600 * UNIT);
        assertEq(token.balanceOf(address(fund)), 600 * UNIT);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 350 * UNIT);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE - 250 * UNIT);
        assertEq(token.allowance(alice, address(fund)), 0);
    }

    function test_RejectZeroContribution() public {
        _contribute(alice, 100 * UNIT);
        _expectContributionFailure(alice, 0, abi.encodeWithSelector(TripFund.ZeroAmount.selector));
    }

    function test_RejectInsufficientBalance() public {
        uint256 amount = INITIAL_BALANCE + 1;
        vm.prank(alice);
        token.approve(address(fund), amount);
        _expectContributionFailure(
            alice,
            amount,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, INITIAL_BALANCE, amount
            )
        );
    }

    function test_RejectInsufficientAllowance() public {
        vm.prank(alice);
        token.approve(address(fund), UNIT);
        _expectContributionFailure(
            alice,
            2 * UNIT,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), UNIT, 2 * UNIT
            )
        );
    }

    function test_ApprovalForImplementationDoesNotApproveProxy() public {
        vm.prank(alice);
        token.approve(implementation, UNIT);
        _expectContributionFailure(
            alice,
            UNIT,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 0, UNIT
            )
        );
    }

    function test_ContributionOneSecondBeforeDeadline() public {
        vm.warp(deadline - 1);
        _contribute(alice, UNIT);
        assertEq(fund.totalRaised(), UNIT);
    }

    function test_RejectContributionAtDeadline() public {
        vm.warp(deadline);
        _expectContributionFailure(
            alice, UNIT, abi.encodeWithSelector(TripFund.DeadlineReached.selector)
        );
    }

    function test_RejectContributionAfterDeadline() public {
        vm.warp(deadline + 1);
        _expectContributionFailure(
            alice, UNIT, abi.encodeWithSelector(TripFund.DeadlineReached.selector)
        );
    }

    function test_ContributionsContinueAfterReachingGoal() public {
        _contribute(alice, GOAL);
        _contribute(bob, UNIT);
        assertEq(fund.totalRaised(), GOAL + UNIT);
    }

    function test_RejectPaymentsBeforeDeadlineBelowGoal() public {
        _contribute(alice, UNIT);
        _expectEarlyPayments();
    }

    function test_RejectPaymentsBeforeDeadlineAtGoal() public {
        _contribute(alice, GOAL);
        _expectEarlyPayments();
    }

    function test_WithdrawAtExactGoal() public {
        _contribute(alice, 400 * UNIT);
        _contribute(bob, 600 * UNIT);
        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), GOAL);
        assertEq(fund.contributions(alice), 400 * UNIT);
        assertEq(fund.contributions(bob), 600 * UNIT);
        assertTrue(fund.withdrawn());
    }

    function test_WithdrawAboveGoal() public {
        _contribute(alice, 400 * UNIT);
        _contribute(bob, 700 * UNIT);
        vm.warp(deadline + 1);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), 1_100 * UNIT);
        assertEq(fund.totalRaised(), 1_100 * UNIT);
    }

    function test_RejectUnauthorizedWithdrawal() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        vm.expectRevert(TripFund.NotOrganizer.selector);
        vm.prank(alice);
        fund.withdraw();
        vm.expectRevert(TripFund.NotOrganizer.selector);
        vm.prank(adminOwner);
        fund.withdraw();
        assertFalse(fund.withdrawn());
        assertEq(token.balanceOf(address(fund)), GOAL);
    }

    function test_RejectRepeatedWithdrawal() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        vm.startPrank(organizer);
        fund.withdraw();
        vm.expectRevert(TripFund.AlreadyWithdrawn.selector);
        fund.withdraw();
        vm.stopPrank();
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function test_RejectWithdrawalBelowGoal() public {
        _contribute(alice, GOAL - 1);
        vm.warp(deadline);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        vm.prank(organizer);
        fund.withdraw();
    }

    function test_RefundsBelowGoal() public {
        _checkRefunds(false);
    }

    function test_RefundsInReverseOrder() public {
        _checkRefunds(true);
    }

    function test_RejectRefundWithoutContribution() public {
        vm.warp(deadline);
        vm.expectRevert(TripFund.NoContribution.selector);
        vm.prank(alice);
        fund.refund();
    }

    function test_RejectRepeatedRefund() public {
        _contribute(alice, UNIT);
        vm.warp(deadline);
        _refund(alice);
        vm.expectRevert(TripFund.NoContribution.selector);
        vm.prank(alice);
        fund.refund();
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
    }

    function test_RejectRefundAtSuccessBeforeAndAfterWithdrawal() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        vm.expectRevert(TripFund.GoalReached.selector);
        vm.prank(alice);
        fund.refund();
        vm.prank(organizer);
        fund.withdraw();
        vm.expectRevert(TripFund.GoalReached.selector);
        vm.prank(alice);
        fund.refund();
    }

    function test_DirectTransferDoesNotMakeFundSuccessful() public {
        _contribute(alice, 400 * UNIT);
        _contribute(bob, 500 * UNIT);
        _donate(200 * UNIT);
        assertEq(fund.totalRaised(), 900 * UNIT);
        assertEq(fund.contributions(carol), 0);
        vm.warp(deadline);
        vm.expectRevert(TripFund.GoalNotReached.selector);
        vm.prank(organizer);
        fund.withdraw();
        _refund(alice);
        _refund(bob);
        assertEq(token.balanceOf(address(fund)), 200 * UNIT);
        assertEq(token.balanceOf(carol), INITIAL_BALANCE - 200 * UNIT);
        assertEq(fund.totalRaised(), 900 * UNIT);
    }

    function test_DirectTransferRemainsAfterWithdrawal() public {
        _contribute(alice, GOAL);
        _donate(200 * UNIT);
        vm.warp(deadline);
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), GOAL);
        assertEq(token.balanceOf(address(fund)), 200 * UNIT);
        assertEq(fund.contributions(carol), 0);
        assertEq(fund.totalRaised(), GOAL);
    }

    function test_ContributionEvent() public {
        vm.prank(alice);
        token.approve(address(fund), UNIT);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Contributed(alice, UNIT);
        vm.prank(alice);
        fund.contribute(UNIT);
    }

    function test_RefundEvent() public {
        _contribute(alice, UNIT);
        vm.warp(deadline);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Refunded(alice, UNIT);
        _refund(alice);
    }

    function test_WithdrawalEvent() public {
        _contribute(alice, GOAL);
        vm.warp(deadline);
        vm.expectEmit(true, false, false, true, address(fund));
        emit Withdrawn(organizer, GOAL);
        vm.prank(organizer);
        fund.withdraw();
    }

    function testFuzz_ContributionsAccumulate(uint256 first, uint256 second) public {
        first = bound(first, 1, INITIAL_BALANCE);
        second = bound(second, 1, INITIAL_BALANCE);
        _contribute(alice, first);
        _contribute(bob, second);
        assertEq(fund.contributions(alice), first);
        assertEq(fund.contributions(bob), second);
        assertEq(fund.totalRaised(), first + second);
        assertEq(token.balanceOf(address(fund)), first + second);
    }

    function testFuzz_RefundsRestoreBalances(uint256 first, uint256 second) public {
        first = bound(first, 1, GOAL / 2 - 1);
        second = bound(second, 1, GOAL / 2 - 1);
        _contribute(alice, first);
        _contribute(bob, second);
        vm.warp(deadline);
        _refund(alice);
        _refund(bob);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE);
        assertEq(token.balanceOf(bob), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(bob), 0);
        assertEq(fund.totalRaised(), first + second);
    }

    function _expectEarlyPayments() private {
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        vm.prank(organizer);
        fund.withdraw();
        vm.expectRevert(TripFund.DeadlineNotReached.selector);
        vm.prank(alice);
        fund.refund();
    }

    function _checkRefunds(bool reverse) private {
        _contribute(alice, 400 * UNIT);
        _contribute(bob, 500 * UNIT);
        vm.warp(deadline);
        address first = reverse ? bob : alice;
        address second = reverse ? alice : bob;
        uint256 secondContribution = fund.contributions(second);
        _refund(first);
        assertEq(fund.contributions(first), 0);
        assertEq(fund.contributions(second), secondContribution);
        assertEq(token.balanceOf(first), INITIAL_BALANCE);
        _refund(second);
        assertEq(token.balanceOf(second), INITIAL_BALANCE);
        assertEq(token.balanceOf(address(fund)), 0);
        assertEq(fund.totalRaised(), 900 * UNIT);
    }
}
