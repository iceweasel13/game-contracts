// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @dev Facilities that can be purchased in game.
 */
struct NewFacility {
    uint256 maxMiners;
    uint256 totalPowerOutput;
    uint256 cost;
    bool inProduction;
    uint256 x; // number of x quadrants
    uint256 y; // number of y qudrants
}
