pragma solidity 0.8.28;

import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TripFund} from "../src/TripFund.sol";
import {TripFundV2} from "../src/TripFundV2.sol";
import {TripFundTest} from "./TripFund.t.sol";
import {FailingERC20} from "./mocks/FailingERC20.sol";

contract TripFundV2Test is TripFundTest {
    event ContributedFor(address indexed payer, address indexed beneficiary, uint256 amount);

    TripFundV2 private v2;

    function setUp() public override {
        super.setUp();
        implementation = address(new TripFundV2());
        fund = _deployFund(implementation, address(token), organizer, GOAL, deadline);
        v2 = TripFundV2(address(fund));
    }

    function test_ContributionForDebitsPayerAndCreditsBeneficiary() public {
        _contributeFor(alice, carol, 100 * UNIT);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 100 * UNIT);
        assertEq(token.balanceOf(carol), INITIAL_BALANCE);
        assertEq(token.allowance(alice, address(fund)), 0);
        assertEq(fund.contributions(alice), 0);
        assertEq(fund.contributions(carol), 100 * UNIT);
        assertEq(fund.totalRaised(), 100 * UNIT);
        assertEq(token.balanceOf(address(fund)), 100 * UNIT);
    }

    function test_ContributionsForAccumulateWithOwnContributions() public {
        _contributeFor(alice, carol, 100 * UNIT);
        _contributeFor(bob, carol, 150 * UNIT);
        _contribute(carol, 50 * UNIT);
        assertEq(fund.contributions(carol), 300 * UNIT);
        assertEq(fund.totalRaised(), 300 * UNIT);
    }

    function test_ContributionForSelf() public {
        _contributeFor(alice, alice, UNIT);
        assertEq(fund.contributions(alice), UNIT);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - UNIT);
    }

    function test_RejectZeroBeneficiary() public {
        _expectForFailure(address(0), UNIT, abi.encodeWithSelector(TripFund.ZeroAddress.selector));
    }

    function test_RejectZeroContributionFor() public {
        _expectForFailure(carol, 0, abi.encodeWithSelector(TripFund.ZeroAmount.selector));
    }

    function test_RejectContributionForWithoutPayerBalance() public {
        uint256 amount = INITIAL_BALANCE + 1;
        vm.prank(alice);
        token.approve(address(fund), amount);
        _expectForFailure(
            carol,
            amount,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, INITIAL_BALANCE, amount
            )
        );
    }

    function test_BeneficiaryApprovalDoesNotReplacePayerApproval() public {
        vm.prank(carol);
        token.approve(address(fund), UNIT);
        _expectForFailure(
            carol,
            UNIT,
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(fund), 0, UNIT
            )
        );
        assertEq(token.allowance(carol, address(fund)), UNIT);
    }

    function test_ContributionForOneSecondBeforeDeadline() public {
        vm.warp(deadline - 1);
        _contributeFor(alice, carol, UNIT);
        assertEq(fund.contributions(carol), UNIT);
    }

    function test_RejectContributionForAtDeadline() public {
        vm.warp(deadline);
        _expectForFailure(carol, UNIT, abi.encodeWithSelector(TripFund.DeadlineReached.selector));
    }

    function test_RejectContributionForAfterDeadline() public {
        vm.warp(deadline + 1);
        _expectForFailure(carol, UNIT, abi.encodeWithSelector(TripFund.DeadlineReached.selector));
    }

    function test_RefundBelongsToBeneficiary() public {
        _contributeFor(alice, carol, 100 * UNIT);
        _contribute(alice, 200 * UNIT);
        vm.warp(deadline);
        _refund(alice);
        _refund(carol);
        assertEq(token.balanceOf(alice), INITIAL_BALANCE - 100 * UNIT);
        assertEq(token.balanceOf(carol), INITIAL_BALANCE + 100 * UNIT);
        assertEq(fund.contributions(carol), 0);
        assertEq(fund.totalRaised(), 300 * UNIT);
        assertEq(token.balanceOf(address(fund)), 0);
        vm.expectRevert(TripFund.NoContribution.selector);
        vm.prank(carol);
        fund.refund();
    }

    function test_PayerCannotRefundBeneficiaryContribution() public {
        _contributeFor(alice, carol, UNIT);
        vm.warp(deadline);
        vm.expectRevert(TripFund.NoContribution.selector);
        vm.prank(alice);
        fund.refund();
        assertEq(fund.contributions(carol), UNIT);
    }

    function test_ContributionForCanReachGoal() public {
        _contributeFor(alice, carol, GOAL);
        vm.warp(deadline);
        vm.expectRevert(TripFund.GoalReached.selector);
        vm.prank(carol);
        fund.refund();
        vm.prank(organizer);
        fund.withdraw();
        assertEq(token.balanceOf(organizer), GOAL);
    }

    function test_ContributionForEvent() public {
        vm.prank(alice);
        token.approve(address(fund), UNIT);
        vm.expectEmit(true, true, false, true, address(fund));
        emit ContributedFor(alice, carol, UNIT);
        vm.prank(alice);
        v2.contributeFor(carol, UNIT);
    }

    function test_ContributionForRollsBackOnTokenRevert() public {
        _checkForTransferFailure(FailingERC20.Failure.Revert);
    }

    function test_ContributionForRollsBackOnFalseReturn() public {
        _checkForTransferFailure(FailingERC20.Failure.ReturnFalse);
    }

    function _checkForTransferFailure(FailingERC20.Failure mode) private {
        FailingERC20 failing = new FailingERC20();
        token = failing;
        _mintParticipants();
        fund = _deployFund(implementation, address(token), organizer, GOAL, deadline);
        v2 = TripFundV2(address(fund));
        vm.prank(alice);
        token.approve(address(fund), UNIT);
        failing.setTransferFromFailure(mode);
        bytes memory reason = mode == FailingERC20.Failure.Revert
            ? abi.encodeWithSelector(FailingERC20.TransferFailed.selector)
            : abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(token));
        _expectForFailure(carol, UNIT, reason);
        failing.setTransferFromFailure(FailingERC20.Failure.None);
        vm.prank(alice);
        v2.contributeFor(carol, UNIT);
        assertEq(fund.contributions(carol), UNIT);
        assertEq(fund.totalRaised(), UNIT);
    }

    function _contributeFor(address payer, address beneficiary, uint256 amount) private {
        vm.startPrank(payer);
        token.approve(address(fund), amount);
        v2.contributeFor(beneficiary, amount);
        vm.stopPrank();
    }

    function _expectForFailure(address beneficiary, uint256 amount, bytes memory reason) private {
        uint256 beneficiaryContribution = fund.contributions(beneficiary);
        uint256 payerContribution = fund.contributions(alice);
        uint256 raised = fund.totalRaised();
        uint256 fundBalance = token.balanceOf(address(fund));
        uint256 payerBalance = token.balanceOf(alice);
        uint256 beneficiaryBalance = token.balanceOf(beneficiary);
        uint256 allowance = token.allowance(alice, address(fund));
        vm.expectRevert(reason);
        vm.prank(alice);
        v2.contributeFor(beneficiary, amount);
        assertEq(fund.contributions(beneficiary), beneficiaryContribution);
        assertEq(fund.contributions(alice), payerContribution);
        assertEq(fund.totalRaised(), raised);
        assertEq(token.balanceOf(address(fund)), fundBalance);
        assertEq(token.balanceOf(alice), payerBalance);
        assertEq(token.balanceOf(beneficiary), beneficiaryBalance);
        assertEq(token.allowance(alice, address(fund)), allowance);
    }
}
