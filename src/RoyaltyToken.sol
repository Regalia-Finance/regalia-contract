// SPDX-License-Identifier: BUSL 1.1
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {PrincipleToken} from "./PrincipleToken.sol";

contract RoyaltyToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable
{
    // errors
    error RT__NotPrincipleToken();
    error RT__NotImplemented();

    address public pt;
    uint256 public ptId;

    constructor() {
        _disableInitializers();
    }

    function initialize(string memory _name, string memory _symbol, address _pt, uint256 _ptId) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Burnable_init();
        __Ownable_init(msg.sender);
        __ERC20Votes_init();
        __ERC20Permit_init(_name);
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

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20VotesUpgradeable)
    {
        // force to self delegate
        // source: https://forum.openzeppelin.com/t/self-delegation-in-erc20votes/17501/17
        if (to != address(0) && numCheckpoints(to) == 0 && delegates(to) == address(0)) {
            _delegate(to, to);
        }
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner);
    }

    function getPastBalance(address account, uint256 blockNumber) public view returns (uint256) {
        return super.getPastVotes(account, blockNumber);
    }

    function getPastVotes(address account, uint256 blockNumber) public view override returns (uint256) {
        revert RT__NotImplemented();
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
