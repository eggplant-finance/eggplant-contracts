/**
 * @title Eggplant Finance Common NFT contract
 */

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./utils/ERC721/ERC721.sol";
import './utils/SafeMath.sol';
import './access/Ownable.sol';
import './access/Roles.sol';
import './utils/Counters.sol';


contract EPCommonNFT is ERC721, Ownable, MinterRole {
    using Counters for Counters.Counter;
    using SafeMath for uint256;


    // NFT Type related info
    struct nftType {
        string title;
        string creator;            // Creator of each NFT
        address creatorAddress;    // Creator's address
        uint256 maxSupply;         // Max supply for each type of NFT
        uint256 mintCount;         // Number of minted NFTs for each type
        uint256 burnCount;         // The burnt amount for each type of NFT
        string tokenURI;           // URI containing the metadata of this NFT
        string nftycode;           // nftycode reference
    }

    // Registry of each NFT Type
    mapping(uint256 => nftType) public nftInfo;
    Counters.Counter private _nftInfoIdx;

    // General token info
    mapping(uint256 => uint256) public tokenNftType;    // The NFT Type for each minted token

    // Records quantity of each NFT type owned by a person
    mapping (address => mapping (uint256 => uint256)) public nftTypeOwned;
    
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {     
    }

    function maxSupplyNFT(uint256 nftTypeId) external view returns (uint256) {
        return nftInfo[nftTypeId].maxSupply;
    }

    function mintCount(uint256 nftTypeId) external view returns (uint256) {
        return nftInfo[nftTypeId].mintCount;
    }

    function burnCount(uint256 nftTypeId) external view returns (uint256) {
        return nftInfo[nftTypeId].burnCount;
    }

    function totalNftTypes() external view returns (uint256) {
        return _nftInfoIdx.current();
    }

    function getNftTypeOwned(address ownerAddr, uint256 nftTypeId) external view returns (uint256) {
        return nftTypeOwned[ownerAddr][nftTypeId];
    }

    function creator(uint256 nftTypeId) external view returns (string memory)  {
        return nftInfo[nftTypeId].creator;
    }

    function nftTypeURI(uint256 nftTypeId) external view returns (string memory) {
        return nftInfo[nftTypeId].tokenURI;
    }

    function setBaseURI(string memory uri) public onlyOwner {
        _setBaseURI(uri);
    }

    function setCreator(uint256 nftTypeId, string memory creatorName, address creatorAddr) public onlyOwner {
        require(nftTypeId <= _nftInfoIdx.current(), "Invalid NFT Type");

        nftInfo[nftTypeId].creator = creatorName;
        nftInfo[nftTypeId].creatorAddress = creatorAddr;
    }

    function setSupply(uint256 nftTypeId, uint256 maxSupply) public onlyOwner {
        require(nftTypeId <= _nftInfoIdx.current(), "Invalid NFT Type");
        require(maxSupply >= nftInfo[nftTypeId].maxSupply, "Max Supply must be set to current or a higher limit");

        nftInfo[nftTypeId].maxSupply = maxSupply;
    }

    function setMetadata(uint256 nftTypeId, string memory uri) public onlyOwner {
        require(nftTypeId <= _nftInfoIdx.current(), "Invalid NFT Type");

        nftInfo[nftTypeId].tokenURI = uri;
    }

    function newNftType(string memory title, string memory creatorName, address creatorAddr, uint256 maxSupply, string memory uri, string memory nftycode) public onlyOwner {
        require (maxSupply > 0, "Supply must be non-zero");

        _nftInfoIdx.increment();
        uint256 newIdx = _nftInfoIdx.current();
        
        nftInfo[newIdx].title = title;
        nftInfo[newIdx].creator = creatorName;
        nftInfo[newIdx].creatorAddress = creatorAddr;
        nftInfo[newIdx].maxSupply = maxSupply;
        nftInfo[newIdx].tokenURI = uri;
        nftInfo[newIdx].nftycode = nftycode;
    }

    function setNftType(uint256 nftTypeId, string memory title, string memory creatorName, address creatorAddr, uint256 maxSupply, string memory uri, string memory nftycode) public onlyOwner {
        require (nftTypeId <= _nftInfoIdx.current(), "Invalid NFT Type");
        require (nftInfo[nftTypeId].mintCount <= maxSupply, "New max supply must be equal or above current supply");

        nftInfo[nftTypeId].title = title;
        nftInfo[nftTypeId].creator = creatorName;
        nftInfo[nftTypeId].creatorAddress = creatorAddr;
        nftInfo[nftTypeId].maxSupply = maxSupply;
        nftInfo[nftTypeId].tokenURI = uri;
        nftInfo[nftTypeId].nftycode = nftycode;
    }

    /** 
	 * @dev Mints an NFT 
     * @param nftTypeId  The NFT Type Id
	 * @param to         The recipient account
	 * @param qty        Amount of NFTs to mint
	 */
    function mint(uint256 nftTypeId, address to, uint256 qty) public virtual onlyMinter {
        require (nftTypeId <= _nftInfoIdx.current(), "Invalid NFT type");
        require (nftInfo[nftTypeId].mintCount.add(qty) <= nftInfo[nftTypeId].maxSupply, "Max supply reached");

        for(uint256 i = 0; i < qty; i++) {
            uint256 mintIdx = totalSupply();
            tokenNftType[mintIdx] = nftTypeId;
            nftInfo[nftTypeId].mintCount = nftInfo[nftTypeId].mintCount.add(1);
            nftTypeOwned[to][nftTypeId] = nftTypeOwned[to][nftTypeId].add(1);

            _safeMint(to, mintIdx);
            _setTokenURI(mintIdx,nftInfo[nftTypeId].tokenURI);
        }
    }

    function burn(uint256 _tokenId) external onlyOwner {
        uint256 nftTypeId = tokenNftType[_tokenId];
        nftInfo[nftTypeId].burnCount = nftInfo[nftTypeId].burnCount.add(1);
        _burn(_tokenId);
    }


}