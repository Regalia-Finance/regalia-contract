// SPDX-License-Identifier: BUSL 1.1
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {RoyaltyToken} from "./RoyaltyToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract PrincipleToken is ERC721, ERC721Burnable, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Math for uint256;

    error PT__NotOwner();
    error PT__InvalidMaturity();
    error PT__NotYetExpired();
    error PT__AlreadyExpired();
    error PT__AlreadyClaimed();
    error PT__LessThanPromised();
    error PT__MoreThanPromised();
    error PT__AlreadySettled();
    error PT__AuctionEnded();
    error PT__NotEnoughBid();
    error PT__AuctionNotExist();
    error PT__AuctionExist();
    error PT__LiquidationPenaltyExceedMax();
    error PT__OwnerAllocationExceeded();
    error PT__PresaleEnded();
    error PT__PresaleNotEnough();
    error PT__PresaleSoldOut();
    error PT__PresaleNotYetEnded();
    error PT__NoWithdrawn();
    error PT__InvalidPresaleEndTime();
    error PT__LessThanMinAmount();

    struct PT {
        address ip; // IP is erc721
        uint256 tokenId;
        uint256 maturity;
        address promisedToken;
        uint256 promisedRoyalty;
        address rt;
    }

    struct PTParams {
        address ip; // IP is erc721
        uint256 tokenId;
        uint256 maturity;
        address promisedToken;
        uint256 promisedRoyalty;
    }

    struct Auction {
        address ip; // IP is erc721
        uint256 tokenId;
        uint256 amount;
        uint256 minAmount;
        uint256 startTime;
        uint256 endTime;
        address bidder;
        bool settled;
    }

    struct Presale {
        uint256 price;
        uint256 endTime;
        uint256 totalAmount;
        uint256 totalSold;
        uint256 totalSales;
        uint256 totalWithdrawn;
    }

    uint256 public constant AUCTION_DURATION = 7 days;

    uint8 public constant MIN_BID_INCREMENT_PERCENTAGE = 1;

    uint256 public currentId;
    address public rtImplementation;
    uint256 public liquidationPenalty;

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => PT) public principles;
    mapping(uint256 => mapping(uint256 => uint256)) public royaltyDistributions;
    mapping(uint256 => uint256) public totalRoyaltyDistributions;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public royaltyClaimed;
    mapping(uint256 => Presale) public presales;

    constructor(address _rtImplementation, uint256 _liquidationPenalty) ERC721("MyToken", "MTK") Ownable(msg.sender) {
        rtImplementation = _rtImplementation;

        if (_liquidationPenalty > 100) revert PT__LiquidationPenaltyExceedMax();
        liquidationPenalty = _liquidationPenalty;
    }

    function depositIP(
        PTParams memory pt,
        Presale memory presale,
        address receiver,
        uint256 rtAmount,
        uint256 ownerAllocation
    ) public nonReentrant {
        if (IERC721Metadata(pt.ip).ownerOf(pt.tokenId) != msg.sender) revert PT__NotOwner();
        if (pt.maturity <= block.timestamp) revert PT__InvalidMaturity();
        if (ownerAllocation > rtAmount) revert PT__OwnerAllocationExceeded();
        if (presale.endTime >= pt.maturity) revert PT__InvalidPresaleEndTime();

        IERC721Metadata(pt.ip).transferFrom(msg.sender, address(this), pt.tokenId);

        uint256 newId = currentId++;

        // Deploy royalty token
        bytes32 salt = keccak256(abi.encodePacked(newId));
        address rt = Clones.cloneDeterministic(rtImplementation, salt);
        RoyaltyToken(rt).initialize(
            IERC721Metadata(pt.ip).name(), IERC721Metadata(pt.ip).symbol(), address(this), newId
        );

        uint256 presaleAllocation = rtAmount - ownerAllocation;
        principles[newId] = PT(pt.ip, pt.tokenId, pt.maturity, pt.promisedToken, pt.promisedRoyalty, rt);
        presales[newId] = Presale(presale.price, presale.endTime, presaleAllocation, 0, 0, 0);

        _safeMint(receiver, newId);
        // Mint owner's share of RT
        RoyaltyToken(rt).mint(receiver, ownerAllocation);
        // Mint the rest of RT to the presale contract
        RoyaltyToken(rt).mint(address(this), presaleAllocation);
    }

    function redeemPT(uint256 id, address receiver) public nonReentrant {
        if (msg.sender != ownerOf(id)) revert PT__NotOwner();
        PT memory pt = principles[id];
        if (block.timestamp < pt.maturity) revert PT__NotYetExpired();
        if (totalRoyaltyDistributions[id] < pt.promisedRoyalty) revert PT__LessThanPromised();

        IERC721Metadata(pt.ip).safeTransferFrom(address(this), receiver, pt.tokenId);
        _burn(id);
    }

    function createAuction(uint256 id) public nonReentrant {
        _createAuction(id);
    }

    function settleAuction(uint256 id) public nonReentrant {
        Auction storage auction = auctions[id];

        if (auction.startTime == 0) revert PT__AuctionNotExist();
        if (auction.endTime > block.timestamp) revert PT__AuctionEnded();
        if (auction.settled) revert PT__AlreadySettled();

        auction.settled = true;

        if (auction.bidder != address(0)) {
            IERC721Metadata(auction.ip).safeTransferFrom(address(this), auction.bidder, auction.tokenId);

            // TODO: penalty ?
            // uint256 liquidationPenaltyAmount = (auction.amount * liquidationPenalty) / 100;
            // uint256 auctionSurplus = auction.amount - principles[id].promisedRoyalty - liquidationPenaltyAmount;
            // if (auctionSurplus > 0) {
            //     IERC20(principles[id].promisedToken).safeTransfer(ownerOf(id), auctionSurplus);
            // }

            // Distribute auction to RT holders
            royaltyDistributions[id][block.number] += auction.amount; //- auctionSurplus;
                // royaltyDistributions[id][block.number] += auction.amount - auctionSurplus;
        } else {
            // Delete auction
            delete auctions[id];

            // start new auction
            _createAuction(id);
        }

        _burn(id);
    }

    function bid(uint256 id, uint256 amount) external nonReentrant {
        Auction storage auction = auctions[id];

        if (auction.startTime == 0) revert PT__AuctionNotExist();
        if (amount < auction.minAmount) revert PT__LessThanMinAmount();
        if (block.timestamp > auction.endTime) revert PT__AuctionEnded();
        if (amount < auction.amount + ((auction.amount * MIN_BID_INCREMENT_PERCENTAGE) / 100)) {
            revert PT__NotEnoughBid();
        }

        address lastBidder = auction.bidder;

        IERC20(principles[id].promisedToken).safeTransferFrom(msg.sender, address(this), amount);

        auction.amount = amount;
        auction.bidder = msg.sender;

        if (lastBidder != address(0)) {
            IERC20(principles[id].promisedToken).safeTransfer(lastBidder, auction.amount);
        }
    }

    function getMaturity(uint256 id) public view returns (uint256) {
        return principles[id].maturity;
    }

    function buyPresale(uint256 id, uint256 amount) public nonReentrant {
        Presale memory presale = presales[id];
        if (block.timestamp > presale.endTime) revert PT__PresaleEnded();
        if (presale.totalSold + amount > presale.totalAmount) revert PT__PresaleNotEnough();

        uint256 sales = amount.mulDiv(presale.price, 1e18); // 1e18 is RT decimals

        presales[id].totalSold += amount;
        presales[id].totalSales += sales;

        IERC20(principles[id].promisedToken).safeTransferFrom(msg.sender, address(this), sales);
        IERC20(principles[id].rt).safeTransfer(msg.sender, amount);
    }

    function withdrawPresaleRevenue(uint256 id) public nonReentrant {
        PT memory pt = principles[id];
        if (ownerOf(id) != msg.sender) revert PT__NotOwner();

        Presale memory presale = presales[id];
        uint256 revenue = presale.totalSales - presale.totalWithdrawn;
        if (revenue == 0) revert PT__NoWithdrawn();

        presales[id].totalWithdrawn += revenue;
        IERC20(principles[id].promisedToken).safeTransfer(ownerOf(id), revenue);
    }

    function withdrawUnsoldPresale(uint256 id) public nonReentrant {
        PT memory pt = principles[id];
        if (ownerOf(id) != msg.sender) revert PT__NotOwner();

        Presale memory presale = presales[id];
        if (block.timestamp < presale.endTime) revert PT__PresaleNotYetEnded();

        uint256 unsoldAmount = presale.totalAmount - presale.totalSold;
        if (unsoldAmount == 0) revert PT__PresaleSoldOut();

        presales[0].totalSold += unsoldAmount;

        IERC20(principles[id].rt).safeTransfer(ownerOf(id), unsoldAmount);
    }

    function depositRoyalty(uint256 id, uint256 amount) public nonReentrant returns (uint256) {
        if (msg.sender != ownerOf(id)) revert PT__NotOwner();
        if (block.timestamp >= principles[id].maturity) revert PT__AlreadyExpired();

        totalRoyaltyDistributions[id] += amount;
        royaltyDistributions[id][block.number] += amount;

        IERC20(principles[id].promisedToken).safeTransferFrom(msg.sender, address(this), amount);

        return block.number;
    }

    function claimRoyalty(uint256 id, uint256 blockNumber, address receiver) public nonReentrant {
        if (royaltyClaimed[id][blockNumber][msg.sender]) revert PT__AlreadyClaimed();

        uint256 rtOwned = RoyaltyToken(principles[id].rt).getPastBalance(msg.sender, blockNumber);
        uint256 totalSupply = RoyaltyToken(principles[id].rt).getPastTotalSupply(blockNumber);
        uint256 totalRoyaltyAmount = royaltyDistributions[id][blockNumber];

        uint256 amount = rtOwned.mulDiv(totalRoyaltyAmount, totalSupply);
        royaltyClaimed[id][blockNumber][msg.sender] = true;
        IERC20(principles[id].promisedToken).safeTransfer(receiver, amount);
    }

    function _createAuction(uint256 id) internal {
        PT memory pt = principles[id];
        if (block.timestamp < pt.maturity) revert PT__NotYetExpired();
        if (pt.promisedRoyalty < totalRoyaltyDistributions[id]) revert PT__MoreThanPromised();
        if (auctions[id].startTime != 0) revert PT__AuctionExist();

        auctions[id] = Auction({
            ip: pt.ip,
            tokenId: pt.tokenId,
            amount: 0,
            minAmount: pt.promisedRoyalty,
            startTime: block.timestamp,
            endTime: block.timestamp + AUCTION_DURATION,
            bidder: address(0),
            settled: false
        });
    }
}
