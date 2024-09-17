// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract PointDutchAuction is ReentrancyGuard, Ownable {
    IERC20 public pointToken;
    address public wallet;
    uint256 public startPrice;
    uint256 public endPrice;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public totalTokens;
    uint256 public tokensSold;
    bool public auctionEnded;

    event AuctionStarted(uint256 startTime, uint256 endTime);
    event TokensPurchased(address indexed buyer, uint256 amount, uint256 price);
    event AuctionEnded(uint256 endTime, uint256 tokensSold);

    constructor(
        address _pointToken,
        address _wallet,
        uint256 _startPrice,
        uint256 _endPrice,
        uint256 _duration,
        uint256 _totalTokens
    )
        Ownable(msg.sender)
    {
        require(_pointToken != address(0), "Invalid token address");
        require(_wallet != address(0), "Invalid wallet address");
        require(_startPrice > _endPrice, "Start price must be greater than end price");
        require(_duration > 0, "Duration must be greater than zero");
        require(_totalTokens > 0, "Total tokens must be greater than zero");

        pointToken = IERC20(_pointToken);
        wallet = _wallet;
        startPrice = _startPrice;
        endPrice = _endPrice;
        totalTokens = _totalTokens;

        // Transfer tokens from owner to this contract
        require(pointToken.transferFrom(msg.sender, address(this), _totalTokens), "Token transfer failed");
    }

    function startAuction() external onlyOwner {
        require(!auctionEnded, "Auction has already ended");
        require(startTime == 0, "Auction has already started");

        startTime = block.timestamp;
        endTime = startTime + (endTime);

        emit AuctionStarted(startTime, endTime);
    }

    function getCurrentPrice() public view returns (uint256) {
        if (block.timestamp < startTime) {
            return startPrice;
        }
        if (block.timestamp >= endTime) {
            return endPrice;
        }

        uint256 timeElapsed = block.timestamp - (startTime);
        uint256 totalDuration = endTime - (startTime);
        uint256 priceDrop = startPrice - (endPrice);

        return startPrice - (priceDrop * (timeElapsed) / (totalDuration));
    }

    function buy() external payable nonReentrant {
        require(startTime > 0, "Auction has not started");
        require(!auctionEnded, "Auction has ended");
        require(block.timestamp < endTime, "Auction has expired");

        uint256 currentPrice = getCurrentPrice();
        uint256 tokensToBuy = msg.value / (currentPrice);
        require(tokensToBuy > 0, "Not enough ETH sent");
        require(tokensSold + (tokensToBuy) <= totalTokens, "Not enough tokens available");

        uint256 cost = tokensToBuy * (currentPrice);
        uint256 refund = msg.value - (cost);

        tokensSold = tokensSold + (tokensToBuy);

        require(pointToken.transfer(msg.sender, tokensToBuy), "Token transfer failed");

        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }

        payable(wallet).transfer(cost);

        emit TokensPurchased(msg.sender, tokensToBuy, currentPrice);

        if (tokensSold == totalTokens) {
            endAuction();
        }
    }

    function endAuction() public {
        require(startTime > 0, "Auction has not started");
        require(!auctionEnded, "Auction has already ended");
        require(block.timestamp >= endTime || tokensSold == totalTokens, "Auction cannot be ended yet");

        auctionEnded = true;

        if (tokensSold < totalTokens) {
            uint256 remainingTokens = totalTokens - (tokensSold);
            require(pointToken.transfer(wallet, remainingTokens), "Token transfer failed");
        }

        emit AuctionEnded(block.timestamp, tokensSold);
    }

    function withdrawUnsoldTokens() external onlyOwner {
        require(auctionEnded, "Auction has not ended");

        uint256 unsoldTokens = pointToken.balanceOf(address(this));
        require(unsoldTokens > 0, "No unsold tokens");

        require(pointToken.transfer(owner(), unsoldTokens), "Token transfer failed");
    }
}
