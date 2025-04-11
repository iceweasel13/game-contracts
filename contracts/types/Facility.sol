// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @dev Current player's facility.
 */
struct Facility {
    uint256 facilityIndex;
    uint256 maxMiners; // x * y
    uint256 currMiners;
    uint256 totalPowerOutput;
    uint256 currPowerOutput;
    uint256 x; // number of x quadrants
    uint256 y; // number of y qudrants
}
