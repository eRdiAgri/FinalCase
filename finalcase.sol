// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "erc721a/contracts/IERC721A.sol"; //ERC721A yi import eder

contract yardimDAO {
    struct Proposal {
        uint yayVotes; //Evet Oyu
        uint nayVotes; //Hayir Oyu
        uint deadline; //Son sure

        address to; //Gonderilecek olan adres
        string description; //Transaction aciklamasi

        mapping(uint => bool) voters; //Adresin oylama yapip yapmadigini kontrol eder
        mapping(address => uint) addressToFundedAmount; //Kimin ne kadar fonladigini tutar
        bool executed; //Gonderilip gonderilmedigini tutar
        uint totalFunded; //Her bir proposalin ne kadar fonlandigini tutar
    }

    mapping(uint => Proposal) public proposals; //Proposallari indexleyecek olan kod
    uint numberOfProposals; //Kac adet proposal oldugunun kaydini tutar
    IERC721A daoNFT; //Kendi interfaceimize ulasacagimiz kod (NFT olup olmadigini tutar)

    constructor(address _nft){ //DAO NFT Interfaceini aktif edecek olan constructor
        daoNFT = IERC721A(_nft);
    }

    enum Vote { //Her bir oy bu veri tipleri kullanilarak verilecektir. 0 ise Yay, 1 ise Nay
        yay, // 0
        nay // 1
    }

    modifier nftHolderOnly() { //NFT Holder olup olmadigini kontrol eder
        require(daoNFT.balanceOf(msg.sender)>0,"not a DAO member"); //msg.sender en az 1 adet NFT tutmali. Aksi taktirde DAO uyesi olmadigi hatasi vermeli.
        _;
    }

    //Proposal olusturma asamasi

    modifier activeProposalOnly(uint _proposalIndex) { //Suresi bitmemis olan proposallar icin oylama verebilsin
        require(block.timestamp < proposals[_proposalIndex].deadline, "proposal is not active");
        _;
    }

    modifier successfulProposalOnly(uint _proposalIndex) { //Yay oylari Nay oylarindan fazlaysa oylama basarili
        require(block.timestamp > proposals[_proposalIndex].deadline, "not yet");
        _;
        require(proposals[_proposalIndex].yayVotes > proposals[_proposalIndex].nayVotes, "not much successful");
    }

    modifier rejectedProposalOnly(uint _proposalIndex) { //Yay oylari Nay oylarindan az ise oylama basarisiz
        require(block.timestamp > proposals[_proposalIndex].deadline, "not yet");
        _;
        require(proposals[_proposalIndex].yayVotes <= proposals[_proposalIndex].nayVotes, "proposal is successful"); //Proposali kontrol eder
    }

    function createProposal(address _to, string memory _description) external nftHolderOnly { //Sadece NFT Holderlarin olusturabilecegi ozelligini iceren fonksiyon
        Proposal storage proposal = proposals[numberOfProposals]; //
        proposal.to = _to; //Fonksiyonu cagaran kisiyi ayarlar
        proposal.description = _description; //Kullanicinin verdigi aciklama
        proposal.deadline = block.timestamp + 1 days; //1 gunluk deadline koyan kisim

        numberOfProposals ++; //Sonraki proposala gecmek icin
    }

    function voteOnProposal(Vote vote, uint proposalIndex, uint[] memory NFTsToVote) //Oy verme fonksiyonu. Kimin kullandigini, hangi proposal icin yaptigini, hangi NFT ile yaptigini tutar.
    external
    nftHolderOnly 
    activeProposalOnly(proposalIndex)
    payable //Oylama yaparken para aktarimi da yapabilir
    {
        uint votePower = NFTsToVote.length; //Oylama gucunu belli eder

        require(votePower > 0, "show some NFTs to vote"); //Oy kullanmak icin 0 dan fazla NFT gostermesi gerekir.

        Proposal storage proposal = proposals[proposalIndex]; //Proposal tanimlanmasi

        for(uint i; i<votePower; i++){ 
            require(daoNFT.ownerOf(NFTsToVote[i]) == msg.sender, "you need to own the NFT"); //NFT olup olmadigini kontrol eder
            require(!proposal.voters[NFTsToVote[i]],"this NFT has already used to vote"); //Onerdigi NFT ile daha once oy kullandi mi kontrol eder.
            proposal.voters[NFTsToVote[i]] = true;
        }

        if(vote == Vote.yay){ //Sundugu oy 0 ise YAY
            proposal.yayVotes += votePower; //Oylama gucu kadar arttir
            proposal.addressToFundedAmount[msg.sender] += msg.value; //Adresin ne kadar fonladigini tutar
            proposal.totalFunded += msg.value; //Total ne kadar tuttugunu msg.value kadar arttirir
        }
        if(vote == Vote.nay){ //Sundugu oy 1 ise NAY
            proposal.nayVotes += votePower; //Oylama gucu kadar arttir
        }
    }

    function executeProposal(uint proposalIndex) external nftHolderOnly successfulProposalOnly(proposalIndex){ //DAO sonucu kabul edildi. Yardim tutari adrese gonderilecek.
        Proposal storage proposal = proposals[proposalIndex];

        require(!proposal.executed, "proposal is already executed"); //Proposal daha once gonderilmemis olmali.

        proposal.executed = true;
        (bool success,) = proposal.to.call{value:proposal.totalFunded}(""); //Success bilgisini tutar
        require(success, "transfer failed"); //Basarili olmasi icin require.
    }

    function retrieveFunds(uint proposalIndex) external nftHolderOnly rejectedProposalOnly(proposalIndex) { //Basarisiz olan proposallar icin insanlar odemelerini geri alabilmeli.
        Proposal storage proposal = proposals[proposalIndex];

        uint funded = proposal.addressToFundedAmount[msg.sender];

        require(funded > 0, "you have not funded");

        proposal.addressToFundedAmount[msg.sender] -= funded;
        (bool success,) = msg.sender.call{value:funded}("");
        require(success, "transfer failed");
    }

    receive() external payable {}

    fallback() external payable {}
}
