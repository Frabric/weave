const { ethers, waffle, network } = require("hardhat");
const { MerkleTree } = require("merkletreejs");

const { assert } = require("chai");
require("chai")
    .use(require("bn-chai")(require("web3").utils.BN))
    .use(require("chai-as-promised"))
    .should();

let deployTestERC20 = require("../scripts/deployTestERC20.js");
let deployUniswap = require("../scripts/deployUniswap.js");
let deployFrabric = require("../scripts/deployFrabric.js");

describe("Frabric Positive Test Cases", accounts => {
  it("should let you add participants", async () => {
    const signers = await ethers.getSigners();

    const usdc = (await deployTestERC20()).address;
    const uniswap = await deployUniswap();
    let genesis = {};
    genesis[signers[2].address] = {
      info: "Test Genesis 0",
      amount: 10
    };
    let { frabric, frbc } = await deployFrabric(usdc, uniswap.router.address, genesis, signers[1].address);

    const merkle = new MerkleTree(
      [signers[3].address, signers[4].address, signers[5].address],
      ethers.utils.keccak256,
      { hashLeaves: true, sortPairs: true }
    );
    frabric = frabric.connect(signers[2]);
    await frabric.proposeParticipants(5, merkle.getHexRoot(), ethers.utils.id("Proposing new participants"));

    // Advance the clock 2 weeks
    await network.provider.request({
      method: "evm_increaseTime",
      params: [2 * 7 * 24 * 60 * 60 + 1]
    });

    // Queue the proposal
    await frabric.queueProposal(1);

    // Advance the clock 48 hours
    await network.provider.request({
      method: "evm_increaseTime",
      params: [2 * 24 * 60 * 60 + 1]
    });

    // Pass it
    await frabric.completeProposal(1);

    // Shim for the fact ethers.js will change this functions names in the future
    const signArgs = [
      {
        name: "Frabric Protocol",
        version: "1",
        chainId: 31337,
        verifyingContract: frabric.address
      },
      {
        KYCVerification: [
          { name: "participant", type: "address" },
          { name: "kycHash", type: "bytes32" }
        ]
      },
      {
        participant: signers[3].address,
        kycHash: "0x0000000000000000000000000000000000000000000000000000000000000003"
      }
    ];
    let signature;
    if (signers[1].signTypedData) {
      signature = await signers[1].signTypedData(...signArgs);
    } else {
      signature = await signers[1]._signTypedData(...signArgs);
    }

    // Approve the participant
    await frabric.approve(
      1,
      signers[3].address,
      "0x0000000000000000000000000000000000000000000000000000000000000003",
      merkle.getHexProof(ethers.utils.keccak256(signers[3].address)),
      signature
    );

    // Verify they were successfully added
    assert.equal(await frabric.participant(signers[3].address), 5);
  });
});
