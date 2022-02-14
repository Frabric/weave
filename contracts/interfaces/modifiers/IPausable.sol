// SPDX-License-Identifier: AGPLv3
pragma solidity >=0.8.9;

interface IPausable {
  event Paused(address account);
  event Unpaused(address account);

  function paused() external view returns (bool);
}
