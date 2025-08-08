// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

contract ProposalVote is Ownable {

    struct Proposal {
        address initiator;              // The initiator of the proposal
        bool activate;                  // Whether the proposal is active
        string proposalDescription;     // The description of the proposal
        uint8[] options;                // The options ID of the proposal
        uint256 proposalId;             // The ID of the proposal
    }

    constructor() Ownable() {
        _proposalId = 0;
    }

    // The minimum pledge quantity required to create a proposal and vote.
    uint256 constant public MINIMUM_PLEDGE_QUANTITY = 10 ether;
    uint8 constant public OPTIONS_LENGTH = 5;
    uint256 private _proposalId;

    // Here are all the proposals.
    mapping(uint256 => Proposal) public proposals;
    // Here is a mapping of address to stake. [vote => balance]
    mapping(address => uint256) public stakingMap;

    // [address => proposal]
    // Here is a mapping of votes to activating proposal.
    // When the proposal is closed, it needs to be removed from the mapping.
    mapping(address => uint256[]) public vote2ActivateStatusProposalMap;

    // [proposal => (address => options[])]
    // Here is a mapping of proposal to voters options.
    // The options corresponds to the off-chain.
    mapping(uint256 => mapping(address => uint8[])) public proposalVoteOptionsMap;

    /// [proposal => (option => uint8(address count))]
    mapping(uint256 => mapping(uint8 => uint8)) public proposalVoteOptionsCountMap;

    // [proposal => (address => voted?)]
    // Here is a status mapping of IDs to votes.
    // If the voter has voted for a proposal, the value is true.
    mapping(uint256 => mapping(address => bool)) public proposalVoteMapCheck;

    // Here is a mapping of proposal to votes address.
    mapping(uint256 => address[]) public proposalVoteMap;

    // Record the voter's created proposal.
    event CreateProposal(address indexed voter, uint256 proposalId);
    event Vote(address indexed voter, uint256 proposalId, uint8[] options);
    event CloseProposal(address indexed voter, uint256 proposalId);
    event Withdraw(address indexed voter, uint256 amount);

    /// @dev Withdraw all.
    function withdraw() public checkBalance payable {
        // Voter can withdraw when the proposal is closed.
        require(vote2ActivateStatusProposalMap[msg.sender].length == 0 && stakingMap[msg.sender] > 0);
        // Withdraw all.
        uint256 amount = stakingMap[msg.sender];
        stakingMap[msg.sender] = 0;
        // // Update state before transfer
        (bool success,) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");
        emit Withdraw(msg.sender, amount);
    }

    /// @dev Close a proposal.
    /// @param proposalId The ID of the proposal.
    function closeProposal(uint256 proposalId) public isInitiator(proposalId) {
        proposals[proposalId].activate = false;
        delete vote2ActivateStatusProposalMap[msg.sender];
        emit CloseProposal(msg.sender, proposalId);
    }

    /// @dev Get proposal information.
    function getProposalInformation(uint256 proposalId) public view returns (Proposal memory) {
        return proposals[proposalId];
    }

    /// @dev Get proposal options choose.
    /// @return The options of the proposal, the key is the option ID, the value is the count.
    function getProposalOptionsChoose(uint256 proposalId) public view returns(uint8[]) {
        return proposalVoteOptionsCountMap[proposalId];
    }

    /// @dev Check if the proposal is initiated or owner by the caller.
    modifier isInitiator(uint256 proposalId) {
        require(proposals[proposalId].initiator == msg.sender || owner == msg.sender);
        _;
    }

    /// @dev Check if the balance is enough to vote.
    modifier checkBalance() {
        // At least MINIMUM_PLEDGE_QUANTITY eth is required to vote and not zero address.
        require(msg.sender != address(0) && stakingMap[msg.sender] >= MINIMUM_PLEDGE_QUANTITY);
        _;
    }

    /// @dev Vote for a proposal.
    /// @param proposalId The ID of the proposal.
    /// @param options The options of the proposal.
    function vote(uint256 proposalId, uint8[] options) public checkBalance {
        require(options.length > 0
        && proposals[proposalId].activate
        && !proposalVoteMapCheck[proposalId][msg.sender]);
        // Add the options to the mapping.
        proposalVoteOptionsMap[proposalId][msg.sender] = options;
        proposalVoteMapCheck[proposalId][msg.sender] = true;
        assembly {
            mstore(0, proposalId)
            mstore(32, proposalVoteMap.slot)
            let voterSlot := keccak256(0, 64)
            let voterLength := sload(voterSlot)
            let voterStorageSlot := add(keccak256(voterSlot, 32), voterLength)
            sstore(voterStorageSlot, caller())
            sstore(voterSlot, add(voterLength, 1))
        }
        assembly {
            mstore(0, caller())
            mstore(32, vote2ActivateStatusProposalMap.slot)
            let proposalSlot := keccak256(0, 64)
            let proposalLength := sload(proposalSlot)
            let proposalStorageSlot := add(keccak256(proposalSlot, 32), proposalLength)
            sstore(proposalStorageSlot, proposalId)
            sstore(proposalSlot, add(proposalLength, 1))
        }
        for (uint8 i = 0; i < options.length; i++) {
            uint8 option = options[i];
            proposalVoteOptionsCountMap[proposalId][option] += 1;
        }
        emit Vote(msg.sender, proposalId, options);
    }

    /// @dev Create a new proposal. At least MINIMUM_PLEDGE_QUANTITY eth is required to create a proposal.
    /// @param proposalDescription The description of the proposal.
    /// @param options The options of the proposal.
    function createProposal(string memory proposalDescription, uint8[] options) external checkBalance {
        require(options.length > 1
        && options.length <= OPTIONS_LENGTH
        && bytes(proposalDescription).length > 0
        && bytes(proposalDescription).length < 1000);
        uint256 proposalId = _getProposalId();
        proposals[proposalId] = Proposal(
            msg.sender,
            true,
            proposalDescription,
            options,
            proposalId);
        emit CreateProposal(msg.sender, proposalId);
    }

    /// @dev At least stake MINIMUM_PLEDGE_QUANTITY eth need to be pledge.
    /// @return True if success.
    function stake() public payable {
        require(msg.value > 0 && msg.sender != address(0));
        uint256 amount = stakingMap[msg.sender];
        require(amount + msg.value >= MINIMUM_PLEDGE_QUANTITY);
        stakingMap[msg.sender] += msg.value;
    }

    /// @dev Get the stake amount.
    function getStakeAmount() public view returns (uint256) {
        return stakingMap[msg.sender];
    }

    /// @dev Get the proposal ID.
    function _getProposalId() private view returns (uint256) {
        return ++_proposalId;
    }
}