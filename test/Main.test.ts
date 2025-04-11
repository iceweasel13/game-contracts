const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MainGame Contract Tests", function () {
  let MainGame, mainGame, FakeBombcoin, fakeBombcoin;
  let owner, user1, user2;
  const initialFacilityPrice =
    ethers.utils.parseEther("0.005");

  beforeEach(async function () {
    [owner, user1, user2, referrer] =
      await ethers.getSigners();

    // Deploy a fake Bombcoin contract for testing
    const FakeBombcoinFactory =
      await ethers.getContractFactory("FakeBombcoin");
    fakeBombcoin = await FakeBombcoinFactory.deploy();
    await fakeBombcoin.deployed();

    // Mint some tokens for user1 and user2 (for testing buyHero, etc.)
    // Let each get 1000 bombcoin tokens (assuming 18 decimals)
    const mintAmount = ethers.utils.parseEther("1000");
    await fakeBombcoin.mint(user1.address, mintAmount);
    await fakeBombcoin.mint(user2.address, mintAmount);

    // Deploy MainGame contract passing necessary parameters (the constructor does not receive parameters)
    const MainGameFactory = await ethers.getContractFactory(
      "MainGame"
    );
    mainGame = await MainGameFactory.deploy();
    await mainGame.deployed();

    // Set bombcoin and bombtoshi in MainGame as needed.
    await mainGame
      .connect(owner)
      .setBigcoin(fakeBombcoin.address);
    await mainGame
      .connect(owner)
      .setBombtoshi(owner.address); // owner will act as bombtoshi for test
  });

  describe("Initial Facility Purchase", function () {
    it("Should allow a new user to purchase initial facility with correct ETH", async function () {
      // user1 sends exact ETH value to purchase initial facility
      await expect(
        mainGame
          .connect(user1)
          .purchaseInitialFacility(referrer.address, {
            value: initialFacilityPrice,
          })
      )
        .to.emit(mainGame, "InitialFacilityPurchased")
        .withArgs(user1.address);

      // Kullanıcının facility bilgileri artık initialize olmuş olmalı.
      const facility = await mainGame.ownerToFacility(
        user1.address
      );
      expect(facility.facilityIndex).to.be.gt(0);
      expect(facility.maxMiners).to.be.gt(0);
    });

    it("Should revert if incorrect ETH value is sent", async function () {
      await expect(
        mainGame
          .connect(user1)
          .purchaseInitialFacility(referrer.address, {
            value: ethers.utils.parseEther("0.01"),
          })
      ).to.be.revertedWith("IncorrectValue"); // Errors.IncorrectValue()
    });

    it("Should revert if the same user attempts to purchase facility twice", async function () {
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
      ).to.be.revertedWith(
        "AlreadyPurchasedInitialFactory"
      );
    });
  });

  describe("Free Starter Hero", function () {
    beforeEach(async function () {
      // Önce user1 facility satın alsın.
      await mainGame
        .connect(user1)
        .purchaseInitialFacility(referrer.address, {
          value: initialFacilityPrice,
        });
    });

    it("Should allow a user to get a free starter hero if not already acquired", async function () {
      // Test için uygun koordinatlar belirleniyor. (Örneğin, facility nin x ve y'si starter facility’den okunuyor)
      const facility = await mainGame.ownerToFacility(
        user1.address
      );
      const x = 1;
      const y = 1;

      await expect(
        mainGame.connect(user1).getFreeStarterHero(x, y)
      )
        .to.emit(mainGame, "MinerBought") // Event is still named MinerBought
        .withArgs(
          user1.address,
          await mainGame.STARTER_HERO_INDEX(),
          0,
          anyValue,
          x,
          y
        );

      // İkinci sefer alınırsa revert etmelidir.
      await expect(
        mainGame.connect(user1).getFreeStarterHero(x, y)
      ).to.be.revertedWith("StarterMinerAlreadyAcquired");
    });

    it("Should revert if invalid coordinates are passed", async function () {
      // Örneğin facility nin sınırlarını aşan koordinatlar
      const facility = await mainGame.ownerToFacility(
        user1.address
      );
      const x = facility.x.toNumber() + 1; // invalid
      const y = 0;
      await expect(
        mainGame.connect(user1).getFreeStarterHero(x, y)
      ).to.be.revertedWith("InvalidMinerCoordinates");
    });
  });

  describe("Buy Hero", function () {
    beforeEach(async function () {
      // Kullanıcı facility satın alsın.
      await mainGame
        .connect(user1)
        .purchaseInitialFacility(referrer.address, {
          value: initialFacilityPrice,
        });
      // Kullanıcının Bombcoin onayını ayarlayalım.
      const heroCost = ethers.utils.parseEther("100"); // test için hero cost değeri, Hero struct içindeki cost'a dikkat.

      // owner contract'a hero ekleyelim (örn: cost 100 bombcoin, inProduction true).
      await mainGame
        .connect(owner)
        .addHero(120, 2, heroCost, true);

      // user1 hero satın alabilmek için Bombcoin transfer onayı versin:
      await fakeBombcoin
        .connect(user1)
        .approve(mainGame.address, heroCost);
    });

    it("Should allow a user to buy a hero if all conditions are met", async function () {
      // Uygun koordinatlar verelim
      const x = 0;
      const y = 0;
      // cost; addHero kullandıktan sonra hero index 2 (starter hero index zaten 1)
      const heroIndex = 2;
      await expect(
        mainGame.connect(user1).buyHero(heroIndex, x, y)
      )
        .to.emit(mainGame, "MinerBought")
        .withArgs(
          user1.address,
          heroIndex,
          anyValue,
          anyValue,
          x,
          y
        );
    });

    it("Should revert buyHero if user has insufficient Bombcoin balance", async function () {
      // user2'nin balance’sı sıfır olsun, bunun için transfer edelim.
      await fakeBombcoin
        .connect(user2)
        .transfer(
          owner.address,
          await fakeBombcoin.balanceOf(user2.address)
        );

      const x = 0;
      const y = 0;
      const heroIndex = 2;
      await expect(
        mainGame.connect(user2).buyHero(heroIndex, x, y)
      ).to.be.revertedWith("TooPoor");
    });
  });

  describe("Sell Hero", function () {
    beforeEach(async function () {
      // Facility satın al, free starter hero al ve ikinci el market için fiyat belirle.
      await mainGame
        .connect(user1)
        .purchaseInitialFacility(referrer.address, {
          value: initialFacilityPrice,
        });
      const x = 0,
        y = 0;
      await mainGame
        .connect(user1)
        .getFreeStarterHero(x, y);
      // Ayarlama: ikinci el market fiyatı ekleniyor
      const starterHeroIndex =
        await mainGame.STARTER_HERO_INDEX();
      await mainGame
        .connect(owner)
        .addSecondaryMarketForHero(
          starterHeroIndex,
          ethers.utils.parseEther("50")
        );
      // Transfer işleminde MainGame kontratında yeterli Bombcoin olması için owner address'ten MainGame'e transfer yapalım.
      await fakeBombcoin
        .connect(owner)
        .mint(
          mainGame.address,
          ethers.utils.parseEther("100")
        );
    });

    it("Should allow a user to sell their hero", async function () {
      // Free starter hero alındıktan sonra, o hero'yu satmaya çalışalım.
      // İlk alınan hero'nun id'sini çekelim.
      const heroIds =
        await mainGame.getPlayerHeroesPaginated(
          user1.address,
          0,
          10
        );
      const heroId = heroIds[0].id;
      await expect(
        mainGame.connect(user1).sellHero(heroId)
      ).to.emit(mainGame, "MinerSold");
    });

    it("Should revert sellHero if the user does not own the hero", async function () {
      await expect(mainGame.connect(user1).sellHero(999)) // olmayan id
        .to.be.revertedWith("PlayerDoesNotOwnMiner");
    });
  });

  describe("Buy New Facility", function () {
    beforeEach(async function () {
      // Purchase initial facility for user1.
      await mainGame
        .connect(user1)
        .purchaseInitialFacility(referrer.address, {
          value: initialFacilityPrice,
        });
      // owner ek olarak yeni facility ekliyor.
      await mainGame
        .connect(owner)
        .addFacility(
          8,
          168,
          ethers.utils.parseEther("1"),
          true,
          4,
          4
        );
    });

    it("Should allow a user to upgrade facility if cooldown is met", async function () {
      // Artık user1 ilk facility'yi aldı.
      // Test için zamanı ileri alalım, Hardhat'ın evm_increaseTime fonksiyonunu kullanabilirsiniz.
      await ethers.provider.send("evm_increaseTime", [
        24 * 3600,
      ]); // 24 saat ilerlet
      await ethers.provider.send("evm_mine", []);

      await expect(
        mainGame.connect(user1).buyNewFacility()
      ).to.emit(mainGame, "FacilityBought");
    });

    it("Should revert if cooldown period has not passed", async function () {
      await expect(
        mainGame.connect(user1).buyNewFacility()
      ).to.be.revertedWith("CantBuyNewFacilityYet");
    });
  });

  describe("Claim Rewards", function () {
    beforeEach(async function () {
      // Purchase facility, get free hero
      await mainGame
        .connect(user1)
        .purchaseInitialFacility(referrer.address, {
          value: initialFacilityPrice,
        });
      await mainGame
        .connect(user1)
        .getFreeStarterHero(0, 0);

      // İki kullanıcının da Bombcoin bakiyeleri hazır, ödüller için zaman ilerletelim.
      await ethers.provider.send("evm_increaseTime", [
        3600,
      ]); // 1 saat
      await ethers.provider.send("evm_mine", []);
    });

    it("Should allow a user to claim rewards when available", async function () {
      // Ödül alınmadan önce pending reward kontrolü yapalım.
      const pendingBefore = await mainGame.pendingRewards(
        user1.address
      );
      expect(pendingBefore).to.be.gt(0);

      // Claim Rewards işlemi
      await expect(
        mainGame.connect(user1).claimRewards()
      ).to.emit(mainGame, "RewardsClaimed");

      // Pending reward sifirlanmalı
      const pendingAfter = await mainGame.pendingRewards(
        user1.address
      );
      expect(pendingAfter).to.equal(0);
    });

    it("Should revert claimRewards if no rewards are pending", async function () {
      // Önce ödül alımını yapalım, sonrasında yeniden claim etmeye çalışalım.
      await mainGame.connect(user1).claimRewards();
      await expect(
        mainGame.connect(user1).claimRewards()
      ).to.be.revertedWith("NoRewardsPending");
    });
  });
});
