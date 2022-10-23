pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Marketplace is ReentrancyGuard {

    address payable public immutable owner;
    uint8 public feePercent;
    uint128 public feeAmount;
    uint16 public itemCount;
    IERC20 public token;

    constructor() {
        owner = payable(msg.sender);
        feePercent = 1;
    }

    struct Item {
        uint16 itemId;
        IERC721 nft;
        uint16 tokenId;
        uint128 price;
        address payable seller;
        bool sold;
    }

    struct auctionPriceStruct {
        uint128 price;
        uint idAddr;
    }

    event Offered(
        uint16 itemId,
        address indexed nft,
        uint16 tokenId,
        uint128 price,
        address indexed seller
    );

    event Bought(
        uint16 itemId,
        address indexed nft,
        uint16 tokenId,
        uint128 price,
        address indexed seller,
        address indexed buyer
    );

    event MakeOffer(
        uint16 itemId,
        address indexed nft,
        uint16 tokenId,
        uint128 offerPrice,
        address indexed seller,
        address indexed buyer
    );

    mapping(uint16 => Item) public items;
    mapping(address => auctionPriceStruct) public auctionPrice;
    address[] public auctionAddr;

    modifier onlyOwner() {
        if(msg.sender != owner) {
            revert();
        }
        _;
    }

    function setToken(IERC20 _token) public onlyOwner {
        token = _token;
    }
    
    function setFeePersent(uint8 _fee) public onlyOwner {
        feePercent = _fee;
    }

    function makeItem(IERC721 _nft, uint16 _tokenId, uint128 _price) external nonReentrant {
        require(_price > 0, "Price must be greater than zero");
        itemCount++;
        _nft.transferFrom(msg.sender, address(this), _tokenId);
        items[itemCount] = Item(
            itemCount,
            _nft,
            _tokenId,
            _price,
            payable(msg.sender),
            false
        );
        emit Offered(
            itemCount,
            address(_nft), 
            _tokenId, _price, 
            msg.sender
        );
    }

    function purchaseItem(uint16 _itemId) external payable nonReentrant {
        require(_itemId > 0 && _itemId <= itemCount, "Item doesnt exist");
        Item memory item = items[_itemId];
        uint128 _totalPrice = item.price + getFeePrice(item.price);
        require(msg.value >= _totalPrice, "Not enough ether to cover item and market fee");
        require(!item.sold, "Item already sold");
        require(item.seller != msg.sender, "Can not buy your own nft");
        token.transferFrom(msg.sender, address(this), _totalPrice);
        SafeERC20.safeTransfer(token, item.seller, item.price);
        setFeeAmount(_totalPrice - item.price);
        items[_itemId].sold = true;
        item.nft.transferFrom(address(this), msg.sender, item.tokenId);
        emit Bought(
            _itemId,
            address(item.nft),
            item.tokenId,
            item.price,
            item.seller,
            msg.sender
        );
    }

    function makeOffer(uint16 _itemId, uint128 _price) external payable nonReentrant {
        require(_itemId > 0 && _itemId <= itemCount, "Item doesnt exist");
        Item memory item = items[_itemId];
        require(_price > 0, "Price must be greater than zero");
        require(!item.sold, "Item already sold");
        require(item.seller != msg.sender, "Can not buy your own nft");
        uint _totalPrice = _price + getFeePrice(_price);
        token.transferFrom(msg.sender, address(this), _totalPrice);
        newAuctionAddr(msg.sender, _price);
        emit MakeOffer(
            _itemId,
            address(item.nft),
            item.tokenId,
            _price,
            item.seller,
            msg.sender
        );
    }

    function Offer(uint16 _itemId) external payable nonReentrant {
        require(_itemId <= itemCount, "Item doesnt exist");
        uint16 _id = getHighestAuctionPrice(_itemId);
        address _highestPriceAddr = auctionAddr[_id];
        uint128 highestPrice = auctionPrice[_highestPriceAddr].price;
        Item memory item = items[_itemId];
        require(!item.sold, "Item already sold");
        require(msg.sender == item.seller, "Only seller NFT can do it");
        SafeERC20.safeTransfer(token, msg.sender, highestPrice);
        item.nft.transferFrom(address(this), _highestPriceAddr, item.tokenId);
        setFeeAmount(getFeePrice(highestPrice));
        for (uint16 _index = 0; _index < getAuctionAddrCount(); _index++) {
            if (_index != _id) {
                address _address = auctionAddr[_index];
                uint128 _totalRefund = auctionPrice[_address].price + getFeePrice(auctionPrice[_address].price);
                SafeERC20.safeTransfer(token, _address, _totalRefund);
            }
        }
        emit Bought(
            _itemId,
            address(item.nft),
            item.tokenId,
            highestPrice,
            msg.sender,
            _highestPriceAddr
        );
    }

    function withdrawFee() public onlyOwner {
        SafeERC20.safeTransfer(token, msg.sender, feeAmount);
        feeAmount = 0;
    }

    function isAuctionAddr(address _address) public view returns (bool) {
        if (auctionAddr.length == 0) return false;
        return (auctionAddr[auctionPrice[_address].idAddr] == _address);
    }

    function getAuctionAddrCount() public view returns(uint256) {
        return auctionAddr.length;
    }

    function newAuctionAddr(address _addr, uint128 _price) public {
        require(!isAuctionAddr(_addr), "This address already exists");
        auctionPrice[_addr].price = _price;
        auctionAddr.push(_addr);
        auctionPrice[_addr].idAddr = getAuctionAddrCount() - 1;
    }

    function getHighestAuctionPrice(uint16 _itemId) public view returns (uint16) {
        require(_itemId <= itemCount, "Item doesnt exist");
        require(getAuctionAddrCount() > 0, "Dont have any offer address");
        uint16 _returnId;
        for (uint16 _id = 0; _id < getAuctionAddrCount(); _id++) {
            address _addr = auctionAddr[_id];
            if(auctionPrice[_addr].price > auctionPrice[auctionAddr[_returnId]].price) {
                _returnId = _id;
            }
        }
        return _returnId;
    }

    function setFeeAmount(uint128 _fee) public {
        feeAmount += _fee;  
    }

    function getFeePrice(uint128 _price) public view returns (uint128) {
        return ((_price * feePercent) / 100);
    }

    function getTotalPriceById(uint16 _itemId) view public returns(uint128){
        return((items[_itemId].price*(100 + feePercent))/100);
    }
}
