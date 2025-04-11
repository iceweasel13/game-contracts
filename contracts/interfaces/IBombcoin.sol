//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

interface IBombcoin {
  function mint(address to, uint256 amt) external;

    function burn(uint256 value) external;

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(address from, address to, uint256 value) external returns (bool);
}