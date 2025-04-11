// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library Errors {
    error IncorrectValue();
    error AlreadyPurchasedInitialFactory();
    error StarterMinerAlreadyAcquired();
    error FacilityAtMaxCapacity();
    error FacilityInadequatePowerOutput();
    error PlayerDoesNotOwnMiner();
    error GreatDepression();
    error MinerNotInProduction();
    error TooPoor();
    error NewFacilityNotInProduction();
    error CannotDowngradeAFacility();
    error NoRewardsPending();
    error CannotDecreaseBelowZero();
    error InvalidMinerCoordinates();
    error FacilityDimensionsInvalid();
    error NeedToInitializeFacility();
    error InvalidReferrer();
    error NonExistentMiner();
    error CantModifyStarterMiner();
    error NonExistentFacility();
    error CantModifyStarterFacility();
    error AlreadyAtMaxFacility();
    error CantBuyNewFacilityYet();
    error InvalidMinerIndex();
    error InvalidFacilityIndex();
    error InvalidFee();
    error InvalidPowerOutput();
    error MiningHasntStarted();
    error WithdrawFailed();
}
