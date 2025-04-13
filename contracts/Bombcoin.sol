//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Bombcoin is ERC20, Ownable {
    error NotMinter();

    uint256 public constant MAX_SUPPLY = 21_000_000e18;

    /// @dev is Main.sol
    address public minter;

    uint256 public amtBurned;

    constructor() ERC20("Bombcoin", "BOMB") {
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Mints tokens when a miner claims their rewards.
     */
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();

        uint256 newSupply = totalSupply() + amount;

        // If minting exceeds max supply, adjust amount to only mint up to MAX_SUPPLY
        if (newSupply > MAX_SUPPLY) {
            amount = MAX_SUPPLY - totalSupply();
        }

        // Only mint if there is still supply left
        if (amount > 0) {
            _mint(to, amount);
        }
    }

    function burn(uint256 value) external {
        amtBurned += value;
        _burn(_msgSender(), value);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }
}
