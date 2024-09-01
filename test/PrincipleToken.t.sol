// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/PrincipleToken.sol";
import "../src/mocks/MockERC721.sol";
import "../src/mocks/MockERC20.sol";
import "../src/RoyaltyToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract PrincipleTokenTest is Test {
    PrincipleToken principleToken;
    RoyaltyToken royaltyToken;
    MockERC721 mockERC721;
    MockERC20 mockERC20;
    address owner = address(0x1);
    address receiver = address(0x2);
    uint256 ip_1 = 1;
    uint256 ip_2 = 2;
    uint256 maturity = block.timestamp + 30 days;
    uint256 rtAmount = 1000e18;
    uint256 promisedRoyalty = 10_000e6; // as USDC
    uint256 ownerAllocation = 100e18; // 10% of rtAmount
    uint256 presaleAllocation = 900e18; // 90% of rtAmount
    uint256 presalePrice = 9e6;

    function setUp() public {
        mockERC721 = new MockERC721();
        mockERC20 = new MockERC20();
        royaltyToken = new RoyaltyToken();
        principleToken = new PrincipleToken(address(royaltyToken), 10);

        // Mint and approve the ERC721 token to the owner
        vm.startPrank(owner);
        mockERC721.mint(owner, ip_1);
        mockERC721.mint(owner, ip_2);
        mockERC721.approve(address(principleToken), ip_1);
        mockERC721.approve(address(principleToken), ip_2);

        // promisedRoyalty
        principleToken.depositIP(
            PrincipleToken.PTParams({
                ip: address(mockERC721),
                tokenId: ip_1,
                maturity: maturity,
                promisedToken: address(mockERC20),
                promisedRoyalty: promisedRoyalty
            }),
            PrincipleToken.Presale({
                price: presalePrice,
                endTime: block.timestamp + 10 days,
                totalAmount: rtAmount,
                totalSold: 0,
                totalSales: 0,
                totalWithdrawn: 0
            }),
            receiver,
            rtAmount,
            ownerAllocation
        );

        // without promisedRoyalty
        principleToken.depositIP(
            PrincipleToken.PTParams({
                ip: address(mockERC721),
                tokenId: ip_2,
                maturity: maturity,
                promisedToken: address(mockERC20),
                promisedRoyalty: 0
            }),
            PrincipleToken.Presale({
                price: presalePrice,
                endTime: block.timestamp + 10 days,
                totalAmount: rtAmount,
                totalSold: 0,
                totalSales: 0,
                totalWithdrawn: 0
            }),
            receiver,
            rtAmount,
            ownerAllocation
        );
        vm.stopPrank();
    }

    function testDepositIP() public {
        (
            address _ip,
            uint256 _tokenId,
            uint256 _maturity,
            address _promisedToken,
            uint256 _promisedRoyalty,
            address _rt
        ) = principleToken.principles(0);
        assertEq(_ip, address(mockERC721));
        assertEq(_tokenId, ip_1);
        assertEq(_maturity, maturity);
        assertEq(_promisedToken, address(mockERC20));
        assertEq(_promisedRoyalty, promisedRoyalty);

        (
            uint256 _price,
            uint256 _endTime,
            uint256 _totalAmount,
            uint256 _totalSold,
            uint256 _totalSales,
            uint256 _totalWithdrawn
        ) = principleToken.presales(0);

        assertEq(_price, presalePrice);

        assertEq(_endTime, _endTime);
        assertEq(_totalAmount, presaleAllocation);
        assertEq(_totalSold, 0);
        assertEq(_totalSales, 0);
        assertEq(_totalWithdrawn, 0);

        assertEq(IERC20(_rt).balanceOf(receiver), ownerAllocation);
        assertEq(IERC20(_rt).balanceOf(address(principleToken)), presaleAllocation);
    }

    function testRedeemPT() public {
        // PT__NotYetExpired
        vm.prank(receiver);
        vm.expectRevert(PrincipleToken.PT__NotYetExpired.selector);
        principleToken.redeemPT(0, receiver);

        // PT__NotOwner
        vm.prank(address(0x3));
        vm.expectRevert(PrincipleToken.PT__NotOwner.selector);
        principleToken.redeemPT(0, receiver);

        vm.warp(maturity + 1);
        vm.startPrank(receiver);
        // PT__LessThanPromised
        vm.expectRevert(PrincipleToken.PT__LessThanPromised.selector);
        principleToken.redeemPT(0, receiver);

        // success
        principleToken.redeemPT(1, receiver);
        assertEq(mockERC721.ownerOf(2), receiver);

        // burned
        vm.expectRevert(abi.encodeWithSignature("ERC721NonexistentToken(uint256)", 1));
        principleToken.ownerOf(1);
        vm.stopPrank();
    }

    function testDepositRoyalty() public {
        mockERC20.mint(receiver, 10_000e6);

        // PT__NotOwner
        vm.prank(address(0x3));
        vm.expectRevert(PrincipleToken.PT__NotOwner.selector);
        principleToken.depositRoyalty(0, 10_000e6);

        vm.startPrank(receiver);
        mockERC20.approve(address(principleToken), 10_000e6);
        principleToken.depositRoyalty(0, 10_000e6);
        assertEq(principleToken.totalRoyaltyDistributions(0), 10_000e6);
        assertEq(mockERC20.balanceOf(address(principleToken)), 10_000e6);

        // PT__AlreadyExpired()
        vm.warp(maturity + 1);
        mockERC20.mint(receiver, 10_000e6);
        vm.expectRevert(PrincipleToken.PT__AlreadyExpired.selector);
        principleToken.depositRoyalty(0, 10_000e6);

        vm.stopPrank();
    }

    function testClaimRoyalty() public {
        vm.startPrank(receiver);
        mockERC20.mint(receiver, 10_000e6);
        mockERC20.approve(address(principleToken), 10_000e6);

        principleToken.depositRoyalty(0, 10_000e6);

        vm.roll(block.number + 1);
        (,,, address _promisedToken,, address _rt) = principleToken.principles(0);
        principleToken.claimRoyalty(0, block.number - 1, address(0x3));
        assertEq(mockERC20.balanceOf(address(0x3)), (10_000e6 * 10) / 100);

        // PT__AlreadyClaimed()
        vm.expectRevert(abi.encodeWithSignature("PT__AlreadyClaimed()"));
        principleToken.claimRoyalty(0, block.number - 1, address(0x3));
        vm.stopPrank();
    }

    function testCreateAuction() public {
        vm.warp(maturity + 1);
        vm.startPrank(address(0x3));
        principleToken.createAuction(0);
        (
            address _ip,
            uint256 _tokenId,
            uint256 _amount,
            uint256 _minAmount,
            uint256 _startTime,
            uint256 _endTime,
            address _bidder,
            bool _settled
        ) = principleToken.auctions(0);
        assertEq(_ip, address(mockERC721));
        assertEq(_tokenId, ip_1);
        assertEq(_amount, 0);
        assertEq(_minAmount, promisedRoyalty);
        assertEq(_startTime, block.timestamp);
        assertEq(_endTime, block.timestamp + 7 days);
        assertEq(_bidder, address(0));
        assertEq(_settled, false);

        vm.stopPrank();
    }

    function testSettleAuction() public {
        vm.warp(maturity + 1);
        principleToken.createAuction(0);

        mockERC20.mint(owner, 30_000e6);

        vm.startPrank(owner);
        mockERC20.approve(address(principleToken), type(uint256).max);

        // bid
        uint256 snapshot = vm.snapshot();
        principleToken.bid(0, 10_000e6);
        vm.warp(block.timestamp + 7 days + 1);
        principleToken.settleAuction(0);

        (,,,,,,, bool _settled) = principleToken.auctions(0);
        assertEq(_settled, true);

        // no bid
        vm.revertTo(snapshot);

        vm.warp(block.timestamp + 7 days + 1);
        principleToken.settleAuction(0);
        (
            address _ip,
            uint256 _tokenId,
            uint256 _amount,
            uint256 _minAmount,
            uint256 _startTime,
            uint256 _endTime,
            address _bidder,
            bool _settled2
        ) = principleToken.auctions(0);
        assertEq(_settled2, false);
        assertEq(_startTime, block.timestamp);
        assertEq(_endTime, block.timestamp + 7 days);
        vm.stopPrank();
    }

    function testBid() public {
        vm.warp(maturity + 1);
        principleToken.createAuction(0);

        mockERC20.mint(owner, 30_000e6);

        vm.startPrank(owner);
        mockERC20.approve(address(principleToken), type(uint256).max);

        // PT__AuctionNotExist()
        vm.expectRevert(abi.encodeWithSignature("PT__AuctionNotExist()"));
        principleToken.bid(99999, 1);

        // PT__LessThanMinAmount()
        vm.expectRevert(abi.encodeWithSignature("PT__LessThanMinAmount()"));
        principleToken.bid(0, 1);

        // success
        principleToken.bid(0, 10_000e6);
        assertEq(mockERC20.balanceOf(address(principleToken)), 10_000e6);

        // PT__NotEnoughBid()
        vm.expectRevert(abi.encodeWithSignature("PT__NotEnoughBid()"));
        principleToken.bid(0, 10_000e6);

        // success on next bid
        (,, uint256 _amount, uint256 _minAmount,,, address _bidder,) = principleToken.auctions(0);
        uint256 nextBid = _amount + ((_amount * principleToken.MIN_BID_INCREMENT_PERCENTAGE()) / 100);

        principleToken.bid(0, nextBid);
        assertEq(mockERC20.balanceOf(address(principleToken)), nextBid);
        assertEq(mockERC20.balanceOf(owner), 30_000e6 - nextBid);
        vm.stopPrank();
    }

    function testBuyPresale() public {
        vm.startPrank(owner);
        mockERC20.mint(owner, 100_000e6);
        mockERC20.approve(address(principleToken), type(uint256).max);

        // PT__PresaleEnded()
        uint256 snapshot = vm.snapshot();
        vm.warp(block.timestamp + 10 days + 1);
        vm.expectRevert(abi.encodeWithSignature("PT__PresaleEnded()"));
        principleToken.buyPresale(0, presaleAllocation);
        vm.revertTo(snapshot);

        // PT__PresaleNotEnough()
        vm.expectRevert(abi.encodeWithSignature("PT__PresaleNotEnough()"));
        principleToken.buyPresale(0, presaleAllocation + 1);

        // success
        principleToken.buyPresale(0, presaleAllocation);

        (uint256 _price,,, uint256 _totalSold, uint256 _totalSales,) = principleToken.presales(0);
        assertEq(_totalSold, presaleAllocation);
        assertEq(_totalSales, (_price * presaleAllocation) / 1e18);

        (,,, address _promisedToken,, address _rt) = principleToken.principles(0);
        assertEq(IERC20(_promisedToken).balanceOf(address(principleToken)), (_price * presaleAllocation) / 1e18);
        assertEq(IERC20(_rt).balanceOf(address(principleToken)), 0);
        vm.stopPrank();
    }

    function testWithdrawPresaleRevenue() public {
        // buy presale
        vm.startPrank(owner);
        mockERC20.mint(owner, 100_000e6);
        mockERC20.approve(address(principleToken), type(uint256).max);
        principleToken.buyPresale(0, presaleAllocation);
        (uint256 _price,,, uint256 _totalSold, uint256 _totalSales, uint256 _totalWithdrawn) =
            principleToken.presales(0);
        vm.stopPrank();

        // withdraw revenue
        vm.startPrank(receiver);
        uint256 balanceBefore = mockERC20.balanceOf(receiver);
        principleToken.withdrawPresaleRevenue(0);
        uint256 balanceAfter = balanceBefore + ((presalePrice * presaleAllocation) / 1e18);
        assertEq(balanceAfter, (presalePrice * presaleAllocation) / 1e18);

        //  PT__NoWithdrawn()
        vm.expectRevert(abi.encodeWithSignature("PT__NoWithdrawn()"));
        principleToken.withdrawPresaleRevenue(0);

        vm.stopPrank();
    }

    function testWithdrawUnsoldPresale() public {
        // PT__NotOwner
        vm.prank(address(0x3));
        vm.expectRevert(abi.encodeWithSignature("PT__NotOwner()"));
        principleToken.withdrawUnsoldPresale(0);

        // PT__PresaleNotYetEnded()
        vm.prank(receiver);
        vm.expectRevert(abi.encodeWithSignature("PT__PresaleNotYetEnded()"));
        principleToken.withdrawUnsoldPresale(0);

        vm.warp(block.timestamp + 11 days);
        vm.startPrank(receiver);
        principleToken.withdrawUnsoldPresale(0);
        (,,,,, address _rt) = principleToken.principles(0);
        assertEq(IERC20(_rt).balanceOf(receiver), 1000e18);

        (
            uint256 _price,
            uint256 _endTime,
            uint256 _totalAmount,
            uint256 _totalSold,
            uint256 _totalSales,
            uint256 _totalWithdrawn
        ) = principleToken.presales(0);

        assertEq(_totalWithdrawn, 0);

        // PT__AlreadyWithdrawn()
        vm.expectRevert(abi.encodeWithSignature("PT__PresaleSoldOut()"));
        principleToken.withdrawUnsoldPresale(0);

        vm.stopPrank();
    }
}
