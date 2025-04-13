import { ethers } from "hardhat";
import { expect } from "chai";
import { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/signers";
import { Contract } from "ethers";

describe("MainGame Contract", function () {
  let bombcoin: Contract;
  let mainGame: any;
  let owner: SignerWithAddress,
    user1: SignerWithAddress,
    user2: SignerWithAddress,
    referrer: SignerWithAddress;

  const initialFacilityPrice = ethers.parseEther("0.005");
  const sampleHeroCost = ethers.parseEther("100");

  beforeEach(async function () {
    [owner, user1, user2, referrer] =
      await ethers.getSigners();

    const BombcoinFactory = await ethers.getContractFactory(
      "Bombcoin"
    );
    bombcoin = await BombcoinFactory.deploy();
    await bombcoin.waitForDeployment();

    const MainGameFactory = await ethers.getContractFactory(
      "MainGame"
    );
    mainGame = await MainGameFactory.deploy();
    await mainGame.waitForDeployment();

    await mainGame.setBigcoin(await bombcoin.getAddress());
    await mainGame.setBombtoshi(owner.address);

    await bombcoin.setMinter(await mainGame.getAddress());
  });

  describe("Initial Setup", function () {
    it("should set correct initial values", async function () {
      expect(await mainGame.bombcoin()).to.equal(
        await bombcoin.getAddress()
      );
      expect(await mainGame.bombtoshi()).to.equal(
        owner.address
      );
      expect(await bombcoin.minter()).to.equal(
        await mainGame.getAddress()
      );
    });
  });

  describe("Initial Facility Purchase", function () {
    it("should allow a new user to purchase initial facility with correct ETH", async function () {
      await expect(
        mainGame
          .connect(user1)
          .purchaseInitialFacility(referrer.address, {
            value: initialFacilityPrice,
          })
      )
        .to.emit(mainGame, "InitialFacilityPurchased")
        .withArgs(user1.address);

      const facility = await mainGame.ownerToFacility(
        user1.address
      );
      expect(facility.facilityIndex).to.be.gt(0);
      expect(facility.maxMiners).to.be.gt(0);
    });

    it("should revert when incorrect ETH value is sent", async function () {
      await expect(
        mainGame
          .connect(user1)
          .purchaseInitialFacility(referrer.address, {
            value: ethers.parseEther("0.01"),
          })
      ).to.be.revertedWithCustomError(
        mainGame,
        "IncorrectValue"
      );
    });

    it("should revert if the same user tries to purchase facility twice", async function () {
      await mainGame
        .connect(user1)
        .purchaseInitialFacility(referrer.address, {
          value: initialFacilityPrice,
        });
      await expect(
        mainGame
          .connect(user1)
          .purchaseInitialFacility(referrer.address, {
            value: initialFacilityPrice,
          })
      ).to.be.revertedWithCustomError(
        mainGame,
        "AlreadyPurchasedInitialFactory"
      );
    });
  });

  describe("Free Starter Hero", function () {
    beforeEach(async function () {
      await mainGame
        .connect(user1)
        .purchaseInitialFacility(referrer.address, {
          value: initialFacilityPrice,
        });
    });

    it("should allow a user to get free starter hero once", async function () {
      const coordX = 1;
      const coordY = 1;
      await expect(
        mainGame
          .connect(user1)
          .getFreeStarterHero(coordX, coordY)
      ).to.emit(mainGame, "MinerBought");

      await expect(
        mainGame
          .connect(user1)
          .getFreeStarterHero(coordX, coordY)
      ).to.be.revertedWithCustomError(
        mainGame,
        "StarterMinerAlreadyAcquired"
      );
    });

    it("should revert if invalid coordinates are provided", async function () {
      const facility = await mainGame.ownerToFacility(
        user1.address
      );
      // Örneğin facility'nin sınırlarından biri: x değeri facility.x ile aynı veya büyük
      const invalidX = Number(facility.x);
      const invalidY = 0;
      await expect(
        mainGame
          .connect(user1)
          .getFreeStarterHero(invalidX, invalidY)
      ).to.be.revertedWithCustomError(
        mainGame,
        "InvalidMinerCoordinates"
      );
    });
  });

  describe("Hero Management", function () {
    beforeEach(async function () {
      await mainGame
        .connect(user1)
        .purchaseInitialFacility(referrer.address, {
          value: initialFacilityPrice,
        });
      await mainGame
        .connect(owner)
        .addHero(120, 2, sampleHeroCost, true);
    });

    it("should allow owner to add new heroes", async function () {
      const heroCount = await mainGame.uniqueHeroCount();
      expect(heroCount).to.be.gt(0);
    });

    it("should revert buyHero if user has insufficient Bombcoin balance", async function () {
      const coordX = 0;
      const coordY = 0;
      await expect(
        mainGame.connect(user1).buyHero(2, coordX, coordY)
      ).to.be.revertedWithCustomError(mainGame, "TooPoor");
    });

    it("should allow buying hero with sufficient Bombcoin balance", async function () {
      // NOT: user1 facility satın alımı zaten önce yapılmış, o yüzden tekrar satın alma çağrısı kaldırıldı.
      await bombcoin.mint(user1.address, sampleHeroCost);
      await mainGame
        .connect(user1)
        .getFreeStarterHero(0, 0);
      // Birkaç blok ilerletelim ki ödüller bir miktar biriksin
      await ethers.provider.send("evm_mine", []);

      // Rewards'ı alarak Bombcoin token kazansın
      await mainGame.connect(user1).claimRewards();

      const coordX = 1;
      const coordY = 1;
      await expect(
        mainGame.connect(user1).buyHero(2, coordX, coordY)
      ).to.emit(mainGame, "MinerBought");
    });
  });

  describe("Rewards System", function () {
    beforeEach(async function () {
      await mainGame
        .connect(user1)
        .purchaseInitialFacility(referrer.address, {
          value: initialFacilityPrice,
        });
      await mainGame
        .connect(user1)
        .getFreeStarterHero(0, 0);
    });

    it("should start mining when first hero is added", async function () {
      expect(await mainGame.miningHasStarted()).to.be.true;
      expect(await mainGame.startBlock()).to.be.gt(0);
    });

    it("should allow claiming rewards", async function () {
      // Birkaç blok madencilik yapalım
      await ethers.provider.send("evm_mine", []);

      await expect(
        mainGame.connect(user1).claimRewards()
      ).to.emit(mainGame, "RewardsClaimed");

      const bombcoinBalance = await bombcoin.balanceOf(
        user1.address
      );
      expect(bombcoinBalance).to.be.gt(0);
    });
  });
});
