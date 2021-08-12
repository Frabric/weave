// SPDX-License-Identifier: AGPLv3
pragma solidity ^0.8.4;

import "../interfaces/dao/IDao.sol";

// Provides functions to be used internally to track proposals and votes
abstract contract Dao is IDao {
  struct ProposalMetaData {
    address creator;
    string info;
    uint256 submitted;
    mapping(address => Vote) voters;
    uint256 votesYes;
    uint256 votesNo;
    uint256 expires;
    uint256 queued;
    bool cancelled;
    bool completed;
  }
  mapping(uint256 => ProposalMetaData) private _proposals;
  uint256 private _nextProposalId;

  function getProposalCreator(uint256 id) external view override returns (address) {
    return _proposals[id].creator;
  }
  function getProposalInfo(uint256 id) external view override returns (string memory) {
    return _proposals[id].info;
  }
  function getVoteStatus(uint256 id, address voter) external view override returns (Vote) {
    return _proposals[id].voters[voter];
  }
  function getTimeSubmitted(uint256 id) external view override returns (uint256) {
    return _proposals[id].submitted;
  }
  function getTimeExpires(uint256 id) external view override returns (uint256) {
    return _proposals[id].expires;
  }
  function getTimeQueued(uint256 id) public view override returns (uint256) {
    return _proposals[id].queued;
  }
  function getCancelled(uint256 id) public view override returns (bool) {
    return _proposals[id].cancelled;
  }
  function getCompleted(uint256 id) public view override returns (bool) {
    return _proposals[id].completed;
  }

  function isProposalActive(uint256 id) public view override returns (bool) {
    return (
      // Proposal must actually exist
      (_proposals[id].submitted != 0) &&
      // Has yet to expire
      (block.timestamp < _proposals[id].expires) &&
      // Wasn't queued
      (_proposals[id].queued == 0) &&
      // Wasn't cancelled
      (!_proposals[id].cancelled) &&
      // Wasn't completed
      (!_proposals[id].completed)
    );
  }

  modifier activeProposal(uint256 id) {
    require(isProposalActive(id), "Dao: Proposal isn't active");
    _;
  }

  // Should only be called by a function which attaches coded meaning to this metadata
  function _createProposal(string calldata info, uint256 expires, uint256 votes) internal returns (uint256 id) {
    id = _nextProposalId;
    _nextProposalId++;

    ProposalMetaData storage proposal = _proposals[id];
    proposal.creator = msg.sender;
    proposal.info = info;
    proposal.submitted = block.timestamp;
    proposal.expires = expires;

    emit NewProposal(id, proposal.creator, proposal.info, block.timestamp, expires);

    _voteYes(id, votes);
  }

  // This activeProposal should be redundant thanks to the below, yet better safe than sorry
  function _removeVotes(uint256 id, uint256 votes) activeProposal(id) internal {
    if (_proposals[id].voters[msg.sender] == Vote.Yes) {
      _proposals[id].votesYes -= votes;
    } else if (_proposals[id].voters[msg.sender] == Vote.No) {
      _proposals[id].votesNo -= votes;
    }
    // Doesn't emit an event and this is either followed up by another set or the event emission
    // Also required due to the definition of abstain
    _proposals[id].voters[msg.sender] = Vote.Abstain;
  }

  function _voteYes(uint256 id, uint256 votes) activeProposal(id) internal {
    // Prevents repeat event emission
    require(_proposals[id].voters[msg.sender] != Vote.Yes, "Dao: Voter already voted yes");
    _removeVotes(id, votes);
    _proposals[id].voters[msg.sender] = Vote.Yes;
    _proposals[id].votesYes += votes;
    emit YesVote(id, msg.sender, votes);
  }

  function _voteNo(uint256 id, uint256 votes) activeProposal(id) internal {
    require(_proposals[id].voters[msg.sender] != Vote.No, "Dao: Voter already voted no");
    _removeVotes(id, votes);
    _proposals[id].voters[msg.sender] = Vote.No;
    _proposals[id].votesNo += votes;
    emit NoVote(id, msg.sender, votes);
  }

  function _abstain(uint256 id, uint256 votes) activeProposal(id) internal {
    require(_proposals[id].voters[msg.sender] != Vote.Abstain, "Dao: Voter already abstained");
    _removeVotes(id, votes);
    // removeVotes sets Abstain so no need to do it here; just emit the event
    emit Abstain(id, msg.sender, votes);
  }

  // Should only be called by something which acts on the coded meaning of this metadata
  function _queueProposal(uint256 id, uint256 totalVotes) activeProposal(id) internal {
    ProposalMetaData storage proposal = _proposals[id];
    require(proposal.votesYes > proposal.votesNo, "Dao: Queueing proposal which didn't pass");
    require((proposal.votesYes + proposal.votesNo) > (totalVotes / 10), "Dao: Proposal didn't have 10% participation");
    proposal.queued = block.timestamp;
    emit ProposalQueued(id);
  }

  function _cancelProposal(uint256 id, address[] calldata voters,
                           uint256[] memory oldVotes, uint256[] memory newVotes) internal {
    require(voters.length == oldVotes.length, "Dao: Length of voters doesn't match length of old votes");
    require(oldVotes.length == newVotes.length, "Dao: Length of voters doesn't match length of new votes");

    uint256 votesYes = _proposals[id].votesYes;
    for (uint256 i = 0; i < voters.length; i++) {
      require(_proposals[id].voters[voters[i]] == Vote.Yes, "Dao: Specified voter didn't vote yes");
      // Should be checked anyways thanks to Solidity's integration of SafeMath
      require(oldVotes[i] > newVotes[i], "Dao: Old amount of votes was not less than the new amount");
      votesYes -= oldVotes[i] - newVotes[i];
    }

    require(votesYes <= _proposals[id].votesNo, "Dao: Cancelling a proposal with more yes votes than no votes");
    _proposals[id].cancelled = true;
    emit ProposalCancelled(id);
  }

  function _completeProposal(uint256 id) internal {
    ProposalMetaData storage proposal = _proposals[id];
    require(proposal.queued != 0, "Dao: Proposal wasn't queued");
    require((proposal.queued + (12 hours)) < block.timestamp, "Dao: Proposal was queued less than 12 hours ago");
    require(!proposal.cancelled, "Dao: Proposal was cancelled");
    require(!proposal.completed, "Dao: Proposal was already completed");
    proposal.completed = true;
    emit ProposalCompleted(id);
  }

  // Enables withdrawing a proposal
  function withdrawProposal(uint256 id) activeProposal(id) external override {
    // Only allow the proposer to withdraw a proposal.
    require(_proposals[id].creator == msg.sender, "Dao: Only the proposal creator may withdraw it");
    // Could also set completed to true; this is more accurate as completed suggests passed.
    // activeProposal will still catch this.
    _proposals[id].expires = 0;
    emit ProposalWithdrawn(id);
  }
}
