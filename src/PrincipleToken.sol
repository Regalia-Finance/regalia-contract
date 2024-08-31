// SPDX-License-Identifier: MIT
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

    struct IP {
        address ip;
        uint256 tokenId;
        uint256 maturity;
        address promisedRoyaltyToken;
        uint256 promisedRoyaltyAmount;
    }

    struct Auction {
        address nft;
        uint256 tokenId;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        address bidder;
        bool settled;
    }

    uint256 public constant AUCTION_DURATION = 7 days;
    uint8 public constant minBidIncrementPercentage = 10;
    uint256 public currentPTId;

    mapping(uint256 => Auction) public auctions;
    mapping(uint256 => address) public royaltyTokens;
    mapping(uint256 => IP) public IPs;
    mapping(uint256 => mapping(uint256 => uint256)) public royaltyDistributions;
    mapping(uint256 => uint256) public totalRoyaltyDistributions;
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) public royaltyClaimed;

    constructor(address initialOwner) ERC721("MyToken", "MTK") Ownable(initialOwner) {}

    function depositIP(
        address ip,
        address receiver,
        uint256 tokenId,
        uint256 maturity,
        uint256 rtAmount,
        address promisedRoyaltyToken,
        uint256 promisedRoyaltyAmount
    ) public nonReentrant {
        if (IERC721Metadata(ip).ownerOf(tokenId) != msg.sender) revert PT__NotOwner();
        if (maturity <= block.timestamp) revert PT__InvalidMaturity();

        IERC721Metadata(ip).transferFrom(msg.sender, address(this), tokenId);

        uint256 newPTId = currentPTId++;
        address rt =
            address(new RoyaltyToken(IERC721Metadata(ip).name(), IERC721Metadata(ip).symbol(), address(this), newPTId));
        royaltyTokens[newPTId] = rt;
        IPs[newPTId] = IP(ip, tokenId, maturity, promisedRoyaltyToken, promisedRoyaltyAmount);

        _safeMint(receiver, newPTId);
        RoyaltyToken(rt).mint(receiver, rtAmount);
    }

    function redeemIP(uint256 ptId, address receiver) public nonReentrant {
        if (msg.sender != ownerOf(ptId)) revert PT__NotOwner();
        IP memory ip = IPs[ptId];
        if (block.timestamp < ip.maturity) revert PT__NotYetExpired();
        if (ip.promisedRoyaltyAmount < totalRoyaltyDistributions[ptId]) revert PT__LessThanPromised();

        IERC721Metadata(ip.ip).transferFrom(address(this), receiver, ip.tokenId);
        _burn(ptId);
    }

    function createAuction(uint256 ptId) public nonReentrant {
        IP memory ip = IPs[ptId];
        if (block.timestamp < ip.maturity) revert PT__NotYetExpired();
        if (ip.promisedRoyaltyAmount > totalRoyaltyDistributions[ptId]) revert PT__MoreThanPromised();

        auctions[ptId] = Auction({
            nft: ip.ip,
            tokenId: ip.tokenId,
            amount: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + AUCTION_DURATION,
            bidder: address(0),
            settled: false
        });
    }

    function settleAuction(uint256 ptId) public nonReentrant {
        Auction storage auction = auctions[ptId];

        if (auction.settled) revert PT__AlreadySettled();
        if (auction.startTime == 0) revert PT__AuctionNotExist();
        if (auction.endTime > block.timestamp) revert PT__AuctionEnded();

        auction.settled = true;

        if (auction.bidder != address(0)) {
            IERC721Metadata(auction.nft).transferFrom(address(this), auction.bidder, auction.tokenId);
        }

        _burn(ptId);
    }

    function bid(uint256 ptId, uint256 amount) external nonReentrant {
        Auction storage auction = auctions[ptId];

        if (auction.nft == address(0)) revert PT__AuctionNotExist();
        if (block.timestamp > auction.endTime) revert PT__AuctionEnded();
        if (amount < auction.amount + ((auction.amount * minBidIncrementPercentage) / 100)) revert PT__NotEnoughBid();

        address lastBidder = auction.bidder;
        if (lastBidder != address(0)) {
            IERC20(IPs[ptId].promisedRoyaltyToken).safeTransfer(lastBidder, auction.amount);
        }

        auction.amount = amount;
        auction.bidder = msg.sender;
    }

    function getMaturity(uint256 ptId) public view returns (uint256) {
        return IPs[ptId].maturity;
    }

    function claimRoyalty(uint256 ptId, uint256 blockNumber, address receiver) public nonReentrant {
        if (royaltyClaimed[ptId][blockNumber][msg.sender]) revert PT__AlreadyClaimed();

        uint256 rtOwned = RoyaltyToken(royaltyTokens[ptId]).getPastVotes(msg.sender, blockNumber);
        uint256 totalSupply = RoyaltyToken(royaltyTokens[ptId]).getPastTotalSupply(blockNumber);
        uint256 amount = royaltyDistributions[ptId][blockNumber];

        uint256 royaltyAmount = rtOwned.mulDiv(amount, totalSupply);
        IERC20(IPs[ptId].promisedRoyaltyToken).safeTransfer(receiver, royaltyAmount);

        royaltyClaimed[ptId][blockNumber][msg.sender] = true;
    }

    function depositRoyalty(uint256 ptId, uint256 amount) public nonReentrant {
        if (msg.sender != ownerOf(ptId)) revert PT__NotOwner();
        if (block.timestamp >= IPs[ptId].maturity) revert PT__AlreadyExpired();

        IERC20(IPs[ptId].promisedRoyaltyToken).safeTransferFrom(msg.sender, address(this), amount);
        totalRoyaltyDistributions[ptId] += amount;
        royaltyDistributions[ptId][block.number] += amount;
    }
}
