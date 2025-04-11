// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @dev Heroes that can be purchased in the game.
 */
struct Hero {
    uint256 heroIndex;       // Eski minerIndex
    uint256 id;              // Oyuncuya ait benzersiz id (free hero alımında veya satın alımda artarak artar)
    uint256 x;               // Yerleştirileceği x koordinatı
    uint256 y;               // Yerleştirileceği y koordinatı
    uint256 power;           // Eski hashrate, hero gücü (mining ya da oyundaki etki gücü)
    uint256 stamina;         // Eski powerConsumption, hero’nun alan kullanım maliyeti (örneğin bomba patlatma/saldırı için gereken enerji)
    uint256 cost;            // Satın alma maliyeti
    bool inProduction;       // Üretimde mi (satın alınabilir durumda mı)
}
