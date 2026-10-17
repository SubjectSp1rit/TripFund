pragma solidity 0.8.28;

import {MockERC20} from "./MockERC20.sol";

contract FailingERC20 is MockERC20 {
    enum Failure {
        None,
        Revert,
        ReturnFalse
    }

    error TransferFailed();

    Failure private transferFailure;
    Failure private transferFromFailure;

    function setTransferFailure(Failure failure) external {
        transferFailure = failure;
    }

    function setTransferFromFailure(Failure failure) external {
        transferFromFailure = failure;
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        if (transferFailure == Failure.Revert) revert TransferFailed();
        if (transferFailure == Failure.ReturnFalse) return false;
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (transferFromFailure == Failure.Revert) revert TransferFailed();
        if (transferFromFailure == Failure.ReturnFalse) return false;
        return super.transferFrom(from, to, value);
    }
}
