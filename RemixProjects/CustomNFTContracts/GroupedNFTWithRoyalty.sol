// contracts/NFTWithRoyalty.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * NFT智能合约，满足ERC721和EIP2981
 * 同时具有如下功能：
 *   分组mint：NFT被分成若干组（group），可mint指定group的NFT，每组数量有限，mint完后无法再mint
 *   定时mint功能：group id从0开始，按照递增方向，每天发行一个
 */
contract GroupedNFT is ERC721Royalty, Ownable {
    uint256[] private _groupCurrentTokenIds;
    uint16 private _nftNumPerGroup; // 每组NFT数量，最多65536个NFT
    address private _defaultRoyaltyReceiver = 0x395aE787f8574f8C87711D417f613e565b5bDa06; // 接受版费的账户
    uint96 _defaultFeeNumerator = 500; // 5%版费
    address private _mintFeeReceiver = 0x395aE787f8574f8C87711D417f613e565b5bDa06; // 接受版费的账户
    uint96 _mintFee = 7250000000000000000; // 7.25 MATIC
    string _defaultBaseURI = "ipfs://bafybeidra7biktwawp62jnyidb2civ4wkiaofyqx35mcneiyocjnogscni/";
    uint256 _ts_base = 1674792000; // timestamp in seconds, 2023.01.27 中午12时
    
    /**
     * groupNum指分组数量，最多2^240组
     * nftNumPerGroup指每组中NFT的数量，最大65536
     * tokenId会被分为groupNum个区间：
     *   group 0: [0, nftNumPerGroup - 1]
     *   group 1: [nftNumPerGroup, 2 * nftNumPerGroup - 1]
     *   ......
     *   group groupNum - 1: [(groupNum - 1) * nftNumPerGroup, groupNum * nftNumPerGroup - 1]
     *
     * 上传NFT数据时需注意上述规律。
     */
    constructor(uint256 groupNum, uint16 nftNumPerGroup) ERC721("GroupedNFT", "GRD") {
        require(groupNum <= 2**240, "group number was too large");
        for(uint256 i = 0;i < groupNum;++i) {
            _groupCurrentTokenIds.push(i * nftNumPerGroup);
        }
        _nftNumPerGroup = nftNumPerGroup;
        _setDefaultRoyalty(_defaultRoyaltyReceiver, _defaultFeeNumerator);
    }

    function _baseURI() internal view override returns (string memory) {
        return _defaultBaseURI;
    }

    /**
     * mint NFT，mint某group中的NFT，
     */
    function mint(address player, uint256 groupId) public payable returns (uint256) {
        require(msg.value >= _mintFee, "Not enough MATIC sent; check price!"); 
        require(groupId < _groupCurrentTokenIds.length , "group ID incorrect");
        require(remainNFTNumByGroupId(groupId) > 0, "group sell out");
        require(!isGroupLocked(groupId), "group locked");

        uint256 newItemId = _groupCurrentTokenIds[groupId];
        _mint(player, newItemId);
        _groupCurrentTokenIds[groupId] += 1;
        return newItemId;
    }

    /**
     * 获取Mint收取的费用总和
     * 只有指定address（_mintFeeReceiver）可以调用该函数
     */
    function getBalance() public view returns(uint) {
        require(msg.sender == _mintFeeReceiver, "Only specified address can withdraw!");
        return address(this).balance;
    }

    /**
      * 将mint NFT收取的费用拿出来
      * 只有指定address（_mintFeeReceiver）可以调用该函数
      */
    function withdrawMintFee() public {
        require(msg.sender == _mintFeeReceiver, "Only specified address can withdraw!");
        address payable to = payable(msg.sender);
        to.transfer(getBalance());
    }

    /**
     * 获取group中剩余NFT数量
     */
    function remainNFTNumByGroupId(uint256 groupId) public view returns (uint16) {
        require(groupId < _groupCurrentTokenIds.length , "group ID incorrect");
        return uint16(_nftNumPerGroup - (_groupCurrentTokenIds[groupId] - _nftNumPerGroup * groupId));
    }

    /**
     * 获取group解锁时间对应的时间戳，采用Unix Timestamp
     */
    function groupUnlockTimeStamp(uint256 groupId) public view returns (uint256) {
        require(groupId < _groupCurrentTokenIds.length , "group ID incorrect");
        // return _ts_base + ((groupId / 3) * 7 + (groupId % 3) * 2) * 1 days; // 每周一三五
        return _ts_base + groupId * 1 days; // 每天一个
    }

    /**
     * 判断group是否被锁定
     */
    function isGroupLocked(uint256 groupId) public view returns (bool) {
        require(groupId < _groupCurrentTokenIds.length , "group ID incorrect");
        return block.timestamp < groupUnlockTimeStamp(groupId);
    }

    /**
     *
     */
    function burn(uint256 tokenId) public onlyOwner {
        require(tokenId == 0, "Can only burn NFT with tokenID 0!");
        _burn(tokenId);
    }

    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);
        _groupCurrentTokenIds[0] -= 1;
        _resetTokenRoyalty(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}