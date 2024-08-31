// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {PrincipleToken} from "./PrincipleToken.sol";

contract RoyaltyToken is ERC20, ERC20Burnable, Ownable, ERC20Permit, ERC20Votes {
    // errors
    error RT__NotPrincipleToken();
    error RT__NotImplemented();

    address public immutable pt;
    uint256 public immutable ptId;

    constructor(string memory _name, string memory _symbol, address _pt, uint256 _ptId)
        ERC20(_name, _symbol)
        Ownable(msg.sender)
        ERC20Permit(_name)
    {
        pt = _pt;
        ptId = _ptId;
    }

    function mint(address to, uint256 amount) public {
        if (msg.sender != pt) {
            revert RT__NotPrincipleToken();
        }

        _mint(to, amount);
    }

    function getPT() public view returns (address) {
        return pt;
    }

    function getPTId() public view returns (uint256) {
        return ptId;
    }

    function getMaturity() public view returns (uint256) {
        return PrincipleToken(pt).getMaturity(ptId);
    }

    function totalSupply() public view override returns (uint256) {
        return (block.timestamp < getMaturity()) ? super.totalSupply() : 0;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return (block.timestamp < getMaturity()) ? super.balanceOf(account) : 0;
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        if (block.timestamp >= getMaturity() && amount != 0) revert ERC20InsufficientBalance(msg.sender, 0, amount);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        if (block.timestamp >= getMaturity() && amount != 0) revert ERC20InsufficientBalance(from, 0, amount);
        return super.transferFrom(from, to, amount);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    function delegate(address delegatee) public virtual override {
        revert RT__NotImplemented();
    }

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        virtual
        override
    {
        revert RT__NotImplemented();
    }
}
