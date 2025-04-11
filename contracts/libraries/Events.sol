// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Events {
    event MiningStarted(uint256 startBlock);

    event NewMinerAdded(
        uint256 indexed minerIndex, uint256 hashRate, uint256 powerConsumption, uint256 cost, bool inProduction
    );

    event MinerProductionToggled(uint256 indexed minerIndex, bool inProduction);

    event FacilityProductionToggled(uint256 indexed facilityIndex, bool inProduction);

    event NewFacilityAdded(
        uint256 indexed facilityIndex, uint256 totalPowerOutput, uint256 cost, bool inProduction, uint256 x, uint256 y
    );

    event MinerSecondaryMarketAdded(uint256 indexed minerIndex, uint256 price);

    event InitialFacilityPurchased(address indexed player);

    event FreeMinerRedeemed(address indexed player);

    event MinerSold(
        address indexed player,
        uint256 indexed minerIndex,
        uint256 secondHandPrice,
        uint256 minerId,
        uint256 x,
        uint256 y
    );

    event MinerBought(
        address indexed player, uint256 indexed minerIndex, uint256 cost, uint256 minerId, uint256 x, uint256 y
    );

    event FacilityBought(address indexed player, uint256 indexed facilityIndex, uint256 cost);

    event PlayerHashrateIncreased(address indexed player, uint256 playerHashrate, uint256 playerPendingRewards);

    event PlayerHashrateDecreased(address indexed player, uint256 playerHashrate, uint256 playerPendingRewards);

    event RewardsClaimed(address indexed player, uint256 rewards);

    event MinerCostChanged(uint256 indexed minerIndex, uint256 newCost);

    event FacilityCostChanged(uint256 indexed facilityIndex, uint256 newCost);
}
