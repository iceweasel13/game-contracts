// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "solady/src/utils/EnumerableSetLib.sol";
import "solady/src/utils/FixedPointMathLib.sol";

import {IBombcoin} from "./interfaces/IBombcoin.sol";

import {Hero} from "./types/Hero.sol";
import {Facility} from "./types/Facility.sol";
import {NewFacility} from "./types/NewFacility.sol";

import {Errors} from "./libraries/Errors.sol";
import {Events} from "./libraries/Events.sol";


contract MainGame is Ownable {
    using EnumerableSetLib for EnumerableSetLib.Uint256Set;

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //            STORAGE
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /// @dev Bombcoin token adresi.
    address public bombcoin;

    /// @dev bombtoshi adresi.
    address public bombtoshi;

    /// @dev Mining başlangıç bloğu.
    uint256 public startBlock;
    bool public miningHasStarted;

    // Her hero'ya benzersiz id ataması yapılır.
    uint256 universalHeroId;

    /// @dev Toplam benzersiz hero sayısı.
    uint256 public uniqueHeroCount;

    /// @dev Toplam facility sayısı.
    uint256 public facilityCount;

    /// @dev Son ödül güncellemesinin yapıldığı blok.
    uint256 public lastRewardBlock;

    /// @dev Toplam network güç (hero power).
    uint256 public totalHashPower;

    /// @dev Bir hash (şimdi hero power) başına düşen kümülatif bombcoin.
    uint256 public cumulativeBombcoinPerPower;

    /// @dev Başlangıç cooldown süresi: 24 saat.
    uint256 public cooldown = 24 hours;

    /// @dev Başlangıç referral ücreti: %2.5.
    uint256 public referralFee = 0.025e18;

    /// @dev Başlangıç yakım oranı: %75.
    uint256 public burnPct = 0.75e18;

    /// @dev Oyuncuların toplam hero power'ı.
    mapping(address => uint256) public playerPower;

    /// @dev Oyuncuların bekleyen ödülleri.
    mapping(address => uint256) public playerPendingRewards;

    /// @dev Oyuncu bombcoin borcu (ödüller güncellendikten sonra).
    mapping(address => uint256) public playerBigcoinDebt;

    /// @dev Farklı hero'ların bilgilerini saklar.
    mapping(uint256 => Hero) public heroes;

    /// @dev Farklı facility'lerin bilgilerini saklar.
    mapping(uint256 => NewFacility) public facilities;

    /// @dev Oyuncunun sahip olduğu hero'ların id'lerini takip eder.
    mapping(address => EnumerableSetLib.Uint256Set) public playerHeroesOwned;

    /// @dev Hero id'sini doğrudan hero yapısına eşler.
    mapping(uint256 => Hero) public playerHeroesId;

    /// @dev Oyuncunun facility bilgileri.
    mapping(address => Facility) public ownerToFacility;

    /// @dev Oyuncuların başlangıçta facility satın alıp almadığını takip eder.
    mapping(address => bool) public initializedStarterFacility;

    /// @dev Oyuncuların ücretsiz başlangıç hero'sunu alıp almadığını takip eder.
    mapping(address => bool) public acquiredStarterHero;

    /// @dev Belirli bir hero için ikinci el pazar fiyatı.
    mapping(uint256 => uint256) public heroSecondHandMarket;

    /// @dev Oyuncuların facility içindeki her bir koordinatta hero olup olmadığını saklar.
    mapping(address => mapping(uint256 => mapping(uint256 => bool))) public playerOccupiedCoords;

    /// @dev Oyuncunun son facility yükseltme zamanını saklar.
    mapping(address => uint256) public lastFacilityUpgradeTimestamp;

    /// @dev Referral için kaydedilen bilgiler.
    mapping(address => address) public referrals;
    mapping(address => address[]) public referredUsers;
    mapping(address => uint256) public referralBonusPaid;

    /// @dev Başlangıç facility satın alma ücreti (ETH cinsinden).
    uint256 public initialFacilityPrice = 0.005 ether;

    /// @dev Başlangıçta verilen hero ve facility index'leri.
    uint256 public immutable STARTER_HERO_INDEX;
    uint256 public immutable STARTER_FACILITY_INDEX;

    /// @dev Her 4.200.000 blokta yarılanma (yaklaşık 50 gün).
    uint256 public constant HALVING_INTERVAL = 4_200_000;

    /// @dev Başlangıçta blok başına 2.5 Bigcoin.
    uint256 public constant INITIAL_BOMBCOIN_PER_BLOCK = 2.5e18;

    uint256 public constant REWARDS_PRECISION = 1e18;

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //          CONSTRUCTOR
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    constructor() {
        _transferOwnership(msg.sender);
        // Starter hero tanımlanır.
        STARTER_HERO_INDEX = ++uniqueHeroCount;

        // Starter ücretsiz hero eklenir. (Satın alınamaz: cost = max, diğer değerler sabit)
        heroes[STARTER_HERO_INDEX] = Hero(
            STARTER_HERO_INDEX,
            type(uint256).max,
            type(uint256).max,
            type(uint256).max,
            100,  // power (güç)
            1,    // stamina (alan tüketimi)
            type(uint256).max, // bu ücretsiz starter hero, satın alınamaz
            false
        );

        // Starter facility eklenir.
        facilities[++facilityCount] = NewFacility(
            4,
            28,
            type(uint256).max, // starter facility; satın alınamaz
            false,
            2,
            2
        );

        STARTER_FACILITY_INDEX = facilityCount;
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        KULLANICI FONKSİYONLARI
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    /**
     * @dev Yeni oyuncuların ilk facility satın alması gerekir.
     */
    function purchaseInitialFacility(address referrer) external payable {
        if (msg.value != initialFacilityPrice) {
            revert Errors.IncorrectValue();
        }
        if (initializedStarterFacility[msg.sender]) {
            revert Errors.AlreadyPurchasedInitialFactory();
        }
        if (referrer == msg.sender) {
            revert Errors.InvalidReferrer();
        }
        initializedStarterFacility[msg.sender] = true;
        if (referrer != address(0)) {
            referrals[msg.sender] = referrer;
            referredUsers[referrer].push(msg.sender);
        }
        NewFacility memory newFacility = facilities[STARTER_FACILITY_INDEX];
        Facility storage facility = ownerToFacility[msg.sender];

        // Oyuncunun starter facility'si initialize edilir.
        facility.facilityIndex = STARTER_FACILITY_INDEX;
        facility.maxMiners = newFacility.maxMiners;
        facility.totalPowerOutput = newFacility.totalPowerOutput;
        facility.x = newFacility.x;
        facility.y = newFacility.y;

        emit Events.InitialFacilityPurchased(msg.sender);
    }

    /**
     * @dev Tüm oyuncular ücretsiz starter hero'larını seçip yerleştirebilir.
     */
    function getFreeStarterHero(uint256 x, uint256 y) external {
        if (acquiredStarterHero[msg.sender]) {
            revert Errors.StarterMinerAlreadyAcquired();
        }
        acquiredStarterHero[msg.sender] = true;

        Hero memory hero = heroes[STARTER_HERO_INDEX];
        Facility storage facility = ownerToFacility[msg.sender];

        if (_isInvalidCoordinates(x, y, facility.x, facility.y)) {
            revert Errors.InvalidMinerCoordinates();
        }
        if (facility.currPowerOutput + hero.stamina > facility.totalPowerOutput) {
            revert Errors.FacilityInadequatePowerOutput();
        }

        hero.x = x;
        hero.y = y;
        hero.id = ++universalHeroId;
        playerOccupiedCoords[msg.sender][x][y] = true;

        playerHeroesOwned[msg.sender].add(universalHeroId);
        playerHeroesId[universalHeroId] = hero;

        // Facility içindeki hero sayısı artırılır.
        facility.currMiners++;
        // Facility'nin tüketilen gücü artar.
        facility.currPowerOutput += hero.stamina;

        emit Events.MinerBought(msg.sender, STARTER_HERO_INDEX, 0, universalHeroId, x, y);
        _increasePower(msg.sender, hero.power);
    }

    /**
     * @dev Bigcoin kullanarak yeni hero satın alma.
     */
    function buyHero(uint256 heroIndex, uint256 x, uint256 y) external {
        Hero memory hero = heroes[heroIndex];
        Facility storage facility = ownerToFacility[msg.sender];

        if (_isInvalidCoordinates(x, y, facility.x, facility.y)) {
            revert Errors.InvalidMinerCoordinates();
        }
        if (!hero.inProduction) revert Errors.MinerNotInProduction();
        if (IBombcoin(bombcoin).balanceOf(msg.sender) < hero.cost) {
            revert Errors.TooPoor();
        }
        if (facility.currPowerOutput + hero.stamina > facility.totalPowerOutput) {
            revert Errors.FacilityInadequatePowerOutput();
        }

        IBombcoin(bombcoin).transferFrom(msg.sender, address(this), hero.cost);
        IBombcoin(bombcoin).burn(FixedPointMathLib.mulWad(hero.cost, burnPct));

        hero.x = x;
        hero.y = y;
        hero.id = ++universalHeroId;
        playerOccupiedCoords[msg.sender][x][y] = true;

        playerHeroesOwned[msg.sender].add(universalHeroId);
        playerHeroesId[universalHeroId] = hero;

        facility.currMiners++;
        facility.currPowerOutput += hero.stamina;

        emit Events.MinerBought(msg.sender, heroIndex, hero.cost, universalHeroId, x, y);
        _increasePower(msg.sender, hero.power);
    }

    /**
     * @dev Oyuncu, ikinci el piyasasında hero satışı yapabilir.
     */
    function sellHero(uint256 heroId) external {
        if (!playerHeroesOwned[msg.sender].contains(heroId)) {
            revert Errors.PlayerDoesNotOwnMiner();
        }
        Hero memory hero = playerHeroesId[heroId];
        uint256 secondHandPrice = heroSecondHandMarket[hero.heroIndex];

        if (secondHandPrice > IBombcoin(bombcoin).balanceOf(address(this))) {
            revert Errors.GreatDepression();
        }
        Facility storage facility = ownerToFacility[msg.sender];

        facility.currMiners--;
        facility.currPowerOutput -= hero.stamina;

        playerHeroesOwned[msg.sender].remove(heroId);
        delete playerHeroesId[heroId];
        playerOccupiedCoords[msg.sender][hero.x][hero.y] = false;

        emit Events.MinerSold(msg.sender, hero.heroIndex, secondHandPrice, heroId, hero.x, hero.y);
        _decreasePower(msg.sender, hero.power);

        if (secondHandPrice > 0) {
            IBombcoin(bombcoin).transfer(msg.sender, secondHandPrice);
        }
    }

    /**
     * @dev Yeni facility yükseltmesi satın alma.
     */
    function buyNewFacility() external {
        if (!initializedStarterFacility[msg.sender]) {
            revert Errors.NeedToInitializeFacility();
        }
        Facility storage currFacility = ownerToFacility[msg.sender];
        uint256 currFacilityIndex = currFacility.facilityIndex;

        if (currFacilityIndex == facilityCount) {
            revert Errors.AlreadyAtMaxFacility();
        }
        if (block.timestamp - lastFacilityUpgradeTimestamp[msg.sender] < cooldown) {
            revert Errors.CantBuyNewFacilityYet();
        }

        NewFacility memory newFacility = facilities[currFacilityIndex + 1];

        if (!newFacility.inProduction) {
            revert Errors.NewFacilityNotInProduction();
        }
        if (IBombcoin(bombcoin).balanceOf(msg.sender) < newFacility.cost) {
            revert Errors.TooPoor();
        }
        IBombcoin(bombcoin).transferFrom(msg.sender, address(this), newFacility.cost);
        IBombcoin(bombcoin).burn(FixedPointMathLib.mulWad(newFacility.cost, burnPct));

        currFacility.facilityIndex++;
        currFacility.maxMiners = newFacility.maxMiners;
        currFacility.totalPowerOutput = newFacility.totalPowerOutput;
        currFacility.x = newFacility.x;
        currFacility.y = newFacility.y;

        lastFacilityUpgradeTimestamp[msg.sender] = block.timestamp;
        emit Events.FacilityBought(msg.sender, currFacility.facilityIndex, newFacility.cost);
    }

    /**
     * @dev Ödüllerin talep edilmesi.
     */
    function claimRewards() external {
        _updateRewards(msg.sender);
        uint256 rewards = playerPendingRewards[msg.sender];
        if (rewards == 0) {
            revert Errors.NoRewardsPending();
        }
        playerPendingRewards[msg.sender] = 0;
        uint256 referralBonus = FixedPointMathLib.mulWad(rewards, referralFee);
        uint256 finalRewards = rewards - referralBonus;

        IBombcoin(bombcoin).mint(msg.sender, finalRewards);
        address referrer = referrals[msg.sender];
        if (referrer != address(0)) {
            IBombcoin(bombcoin).mint(referrer, referralBonus);
            referralBonusPaid[referrer] += referralBonus;
        } else {
            IBombcoin(bombcoin).mint(address(this), referralBonus);
            referralBonusPaid[address(this)] += referralBonus;
        }
        emit Events.RewardsClaimed(msg.sender, rewards);
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //       INTERNAL FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function _updateCumulativeRewards() internal {
        if (totalHashPower == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 currentBlock = lastRewardBlock;
        uint256 lastBombcoinPerBlock =
            INITIAL_BOMBCOIN_PER_BLOCK / (2 ** ((lastRewardBlock - startBlock) / HALVING_INTERVAL));

        while (currentBlock < block.number) {
            uint256 nextHalvingBlock =
                (startBlock % HALVING_INTERVAL) + ((currentBlock / HALVING_INTERVAL) + 1) * HALVING_INTERVAL;
            uint256 endBlock = (nextHalvingBlock < block.number) ? nextHalvingBlock : block.number;

            cumulativeBombcoinPerPower +=
                ((lastBombcoinPerBlock * (endBlock - currentBlock) * REWARDS_PRECISION) / totalHashPower);

            currentBlock = endBlock;
            if (currentBlock == nextHalvingBlock) {
                lastBombcoinPerBlock /= 2;
            }
        }
        lastRewardBlock = block.number;
    }

    function _updateRewards(address player) internal {
        _updateCumulativeRewards();

        playerPendingRewards[player] +=
            (playerPower[player] * (cumulativeBombcoinPerPower - playerBigcoinDebt[player])) / REWARDS_PRECISION;

        playerBigcoinDebt[player] = cumulativeBombcoinPerPower;
    }

    function _increasePower(address player, uint256 power) internal {
        if (!miningHasStarted) {
            miningHasStarted = true;
            startBlock = block.number;
            lastRewardBlock = block.number;
            emit Events.MiningStarted(startBlock);
        }
        _updateRewards(player);

        totalHashPower += power;
        playerPower[player] += power;

        emit Events.PlayerHashrateIncreased(msg.sender, playerPower[msg.sender], playerPendingRewards[msg.sender]);
    }

    function _decreasePower(address player, uint256 power) internal {
        _updateRewards(player);

        totalHashPower -= power;
        playerPower[player] -= power;

        emit Events.PlayerHashrateDecreased(msg.sender, playerPower[msg.sender], playerPendingRewards[msg.sender]);
    }

    function _isInvalidCoordinates(uint256 desiredX, uint256 desiredY, uint256 facilityX, uint256 facilityY)
        internal
        view
        returns (bool)
    {
        if (desiredX >= facilityX || desiredY >= facilityY) {
            return true;
        }
        return playerOccupiedCoords[msg.sender][desiredX][desiredY];
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //         VIEW FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function getBigcoinPerBlock() public view returns (uint256) {
        if (!miningHasStarted) {
            return 0;
        }

        uint256 halvingsSinceStart = (block.number - startBlock) / HALVING_INTERVAL;
        return INITIAL_BOMBCOIN_PER_BLOCK / (2 ** halvingsSinceStart);
    }

    function pendingRewards(address player) external view returns (uint256) {
        if (!miningHasStarted) {
            return 0;
        }

        if (totalHashPower == 0) {
            return FixedPointMathLib.mulWad(playerPendingRewards[player], 1e18 - referralFee);
        }

        uint256 currentBlock = lastRewardBlock;
        uint256 lastBombcoinPerBlock =
            INITIAL_BOMBCOIN_PER_BLOCK / (2 ** ((lastRewardBlock - startBlock) / HALVING_INTERVAL));

        uint256 simulatedCumulativeBigcoinPerPower = cumulativeBombcoinPerPower;

        while (currentBlock < block.number) {
            uint256 nextHalvingBlock =
                (startBlock % HALVING_INTERVAL) + ((currentBlock / HALVING_INTERVAL) + 1) * HALVING_INTERVAL;
            uint256 endBlock = (nextHalvingBlock < block.number) ? nextHalvingBlock : block.number;

            if (totalHashPower > 0) {
                simulatedCumulativeBigcoinPerPower +=
                    ((lastBombcoinPerBlock * (endBlock - currentBlock) * REWARDS_PRECISION) / totalHashPower);
            }

            currentBlock = endBlock;
            if (currentBlock == nextHalvingBlock) {
                lastBombcoinPerBlock /= 2;
            }
        }

        return FixedPointMathLib.mulWad(
            playerPendingRewards[player]
                + ((playerPower[player] * (simulatedCumulativeBigcoinPerPower - playerBigcoinDebt[player]))
                    / REWARDS_PRECISION),
            1e18 - referralFee
        );
    }

    function playerBigcoinPerBlock(address player) external view returns (uint256) {
        if (totalHashPower == 0) {
            return 0;
        }

        uint256 currBigcoinPerBlock =
            INITIAL_BOMBCOIN_PER_BLOCK / (2 ** ((block.number - startBlock) / HALVING_INTERVAL));

        return FixedPointMathLib.mulDiv(playerPower[player], currBigcoinPerBlock, totalHashPower);
    }

    function blocksUntilNextHalving() external view returns (uint256) {
        if (startBlock == 0) revert Errors.MiningHasntStarted();

        uint256 nextHalvingBlock =
            (startBlock % HALVING_INTERVAL) + ((block.number / HALVING_INTERVAL) + 1) * HALVING_INTERVAL;

        return nextHalvingBlock - block.number;
    }

    function timeUntilNextFacilityUpgrade(address player) external view returns (uint256) {
        if (lastFacilityUpgradeTimestamp[player] + cooldown < block.timestamp) {
            return 0;
        }
        return (lastFacilityUpgradeTimestamp[player] + cooldown) - block.timestamp;
    }

    function getPlayerHeroesPaginated(address player, uint256 startIndex, uint256 size)
        external
        view
        returns (Hero[] memory)
    {
        EnumerableSetLib.Uint256Set storage set = playerHeroesOwned[player];
        uint256 length = set.length();

        if (startIndex >= length) {
            return new Hero[](0);
        }

        uint256 remaining = length - startIndex;
        uint256 returnSize = size > remaining ? remaining : size;

        Hero[] memory playerHeroes = new Hero[](returnSize);
        for (uint256 i = 0; i < returnSize; i++) {
            playerHeroes[i] = playerHeroesId[set.at(startIndex + i)];
        }

        return playerHeroes;
    }

    function getReferrals(address referrer) external view returns (address[] memory) {
        return referredUsers[referrer];
    }

    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
    //        OWNER FUNCTIONS
    // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

    function addHero(uint256 power, uint256 stamina, uint256 cost, bool inProduction) external onlyOwner {
        ++uniqueHeroCount;
        heroes[uniqueHeroCount] = Hero(uniqueHeroCount, 0, 0, 0, power, stamina, cost, inProduction);
        emit Events.NewMinerAdded(uniqueHeroCount, power, stamina, cost, inProduction);
    }

    function toggleHeroProduction(uint256 heroIndex, bool inProduction) external onlyOwner {
        if (heroIndex < STARTER_HERO_INDEX || heroIndex > uniqueHeroCount) {
            revert Errors.InvalidMinerIndex();
        }
        Hero storage hero = heroes[heroIndex];
        hero.inProduction = inProduction;
        emit Events.MinerProductionToggled(heroIndex, inProduction);
    }

    function addFacility(
        uint256 maxMiners,
        uint256 totalPowerOutput,
        uint256 cost,
        bool inProduction,
        uint256 x,
        uint256 y
    ) external onlyOwner {
        if (x * y != maxMiners) {
            revert Errors.FacilityDimensionsInvalid();
        }
        if (facilities[facilityCount].x > x || facilities[facilityCount].y > y) {
            revert Errors.FacilityDimensionsInvalid();
        }
        if (facilities[facilityCount].totalPowerOutput > totalPowerOutput) {
            revert Errors.InvalidPowerOutput();
        }
        facilities[++facilityCount] = NewFacility(maxMiners, totalPowerOutput, cost, inProduction, x, y);

        emit Events.NewFacilityAdded(facilityCount, totalPowerOutput, cost, inProduction, x, y);
    }

    function toggleFacilityProduction(uint256 facilityIndex, bool inProduction) external onlyOwner {
        if (facilityIndex < STARTER_FACILITY_INDEX || facilityIndex > facilityCount) {
            revert Errors.InvalidFacilityIndex();
        }

        NewFacility storage facility = facilities[facilityIndex];
        facility.inProduction = inProduction;

        emit Events.FacilityProductionToggled(facilityIndex, inProduction);
    }

    function addSecondaryMarketForHero(uint256 heroIndex, uint256 price) external onlyOwner {
        heroSecondHandMarket[heroIndex] = price;

        emit Events.MinerSecondaryMarketAdded(heroIndex, price);
    }

    function setBigcoin(address _bombcoin) external onlyOwner {
        bombcoin = _bombcoin;
    }

    function setBombtoshi(address _bombtoshi) external onlyOwner {
        bombtoshi = _bombtoshi;
    }

    function setInitialFacilityPrice(uint256 _initialPrice) external onlyOwner {
        initialFacilityPrice = _initialPrice;
    }

    function setReferralFee(uint256 fee) external onlyOwner {
        if (fee > 1e18) revert Errors.InvalidFee();

        referralFee = fee;
    }

    function setBurnPct(uint256 burn) external onlyOwner {
        if (burn > 1e18) revert Errors.InvalidFee();

        burnPct = burn;
    }

    function setCooldown(uint256 _cooldown) external onlyOwner {
        cooldown = _cooldown;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = payable(bombtoshi).call{value: balance}("");

        if (!success) revert Errors.WithdrawFailed();
    }

    function withdrawBombcoin(uint256 amt) external onlyOwner {
        IBombcoin(bombcoin).transfer(bombtoshi, amt);
    }

    function changeHeroCost(uint256 heroIndex, uint256 newCost) external onlyOwner {
        if (heroIndex > uniqueHeroCount) {
            revert Errors.NonExistentMiner();
        }
        if (heroIndex == STARTER_HERO_INDEX) {
            revert Errors.CantModifyStarterMiner();
        }
        Hero storage hero = heroes[heroIndex];
        hero.cost = newCost;
        emit Events.MinerCostChanged(heroIndex, newCost);
    }

    function changeFacilityCost(uint256 facilityIndex, uint256 newCost) external onlyOwner {
        if (facilityIndex > facilityCount) {
            revert Errors.NonExistentFacility();
        }
        if (facilityIndex == STARTER_FACILITY_INDEX) {
            revert Errors.CantModifyStarterFacility();
        }
        NewFacility storage facility = facilities[facilityIndex];
        facility.cost = newCost;
        emit Events.FacilityCostChanged(facilityIndex, newCost);
    }
}
