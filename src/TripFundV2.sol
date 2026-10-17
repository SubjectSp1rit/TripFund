pragma solidity 0.8.28;

import {TripFund} from "./TripFund.sol";

contract TripFundV2 is TripFund {
    event ContributedFor(address indexed payer, address indexed beneficiary, uint256 amount);

    function contributeFor(address beneficiary, uint256 amount) external {
        _contribute(beneficiary, amount);
        emit ContributedFor(msg.sender, beneficiary, amount);
    }
}
