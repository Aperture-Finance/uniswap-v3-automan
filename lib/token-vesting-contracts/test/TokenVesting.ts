import { ethers } from "hardhat";
import { expect } from "chai";
import {
  MockTokenVesting,
  MockTokenVesting__factory,
  Token,
  Token__factory,
  TokenVesting,
} from "../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

describe("TokenVesting", function () {
  let TokenFactory: Token__factory;
  let testToken: Token;
  let TokenVestingFactory: MockTokenVesting__factory;
  let tokenVesting: MockTokenVesting;
  let owner: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let addrs: SignerWithAddress[];
  const baseTime = 1622551248;
  const startTime = baseTime;
  const cliff = 0;
  const duration = 1000;
  const revocable = true;
  const amountTotal = 100;

  before(async function () {
    TokenFactory = await ethers.getContractFactory("Token");
    TokenVestingFactory = await ethers.getContractFactory("MockTokenVesting");
  });
  beforeEach(async function () {
    [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
    testToken = await TokenFactory.deploy("Test Token", "TT", 1000000);
    await testToken.deployed();
    // deploy vesting contract
    tokenVesting = await TokenVestingFactory.deploy(testToken.address);
    await tokenVesting.deployed();
    expect(await tokenVesting.getToken()).to.equal(testToken.address);
  });

  describe("Vesting", function () {
    it("Should assign the total supply of tokens to the owner", async function () {
      const ownerBalance = await testToken.balanceOf(owner.address);
      expect(await testToken.totalSupply()).to.equal(ownerBalance);
    });

    it("Should vest tokens gradually", async function () {
      // send tokens to vesting contract
      await expect(testToken.transfer(tokenVesting.address, 1000))
        .to.emit(testToken, "Transfer")
        .withArgs(owner.address, tokenVesting.address, 1000);
      const vestingContractBalance = await testToken.balanceOf(
        tokenVesting.address
      );
      expect(vestingContractBalance).to.equal(1000);
      expect(await tokenVesting.getWithdrawableAmount()).to.equal(1000);

      const beneficiary = addr1;
      const schedule: TokenVesting.VestingScheduleStruct = {
        initialized: true,
        revocable,
        revoked: false,
        beneficiary: beneficiary.address,
        start: startTime,
        cliff: startTime + cliff,
        duration,
        amountTotal,
        released: 0,
      };
      // create new vesting schedule
      await tokenVesting.createVestingSchedule(schedule);
      expect(await tokenVesting.getVestingSchedulesCount()).to.be.equal(1);
      expect(
        await tokenVesting.getVestingSchedulesCountByBeneficiary(
          beneficiary.address
        )
      ).to.be.equal(1);

      // compute vesting schedule id
      const vestingScheduleId =
        await tokenVesting.computeVestingScheduleIdForAddressAndIndex(
          beneficiary.address,
          0
        );

      // check that vested amount is 0
      expect(
        await tokenVesting.computeReleasableAmount(vestingScheduleId)
      ).to.be.equal(0);

      // set time to half the vesting period
      const halfTime = baseTime + duration / 2;
      await tokenVesting.setCurrentTime(halfTime);

      // check that vested amount is half the total amount to vest
      expect(
        await tokenVesting
          .connect(beneficiary)
          .computeReleasableAmount(vestingScheduleId)
      ).to.be.equal(50);

      // check that only beneficiary can try to release vested tokens
      await expect(
        tokenVesting.connect(addr2).release(vestingScheduleId, 100)
      ).to.be.revertedWithCustomError(tokenVesting, "OnlyBeneficiaryOrOwner");

      // release 10 tokens and check that a Transfer event is emitted with a value of 10
      await expect(
        tokenVesting.connect(beneficiary).release(vestingScheduleId, 10)
      )
        .to.emit(testToken, "Transfer")
        .withArgs(tokenVesting.address, beneficiary.address, 10);

      // check that the vested amount is now 40
      expect(
        await tokenVesting
          .connect(beneficiary)
          .computeReleasableAmount(vestingScheduleId)
      ).to.be.equal(40);
      let vestingSchedule: TokenVesting.VestingScheduleStructOutput =
        await tokenVesting.getVestingSchedule(vestingScheduleId);

      // check that the released amount is 10
      expect(vestingSchedule.released).to.be.equal(10);

      // set current time after the end of the vesting period
      await tokenVesting.setCurrentTime(baseTime + duration + 1);

      // check that the vested amount is 90
      expect(
        await tokenVesting
          .connect(beneficiary)
          .computeReleasableAmount(vestingScheduleId)
      ).to.be.equal(90);

      // beneficiary release vested tokens (45)
      await expect(
        tokenVesting.connect(beneficiary).release(vestingScheduleId, 45)
      )
        .to.emit(testToken, "Transfer")
        .withArgs(tokenVesting.address, beneficiary.address, 45);

      // owner release vested tokens (45)
      await expect(tokenVesting.connect(owner).release(vestingScheduleId, 45))
        .to.emit(testToken, "Transfer")
        .withArgs(tokenVesting.address, beneficiary.address, 45);
      vestingSchedule = await tokenVesting.getVestingSchedule(
        vestingScheduleId
      );

      // check that the number of released tokens is 100
      expect(vestingSchedule.released).to.be.equal(100);

      // check that the vested amount is 0
      expect(
        await tokenVesting
          .connect(beneficiary)
          .computeReleasableAmount(vestingScheduleId)
      ).to.be.equal(0);

      // check that anyone cannot revoke a vesting
      await expect(
        tokenVesting.connect(addr2).revoke(vestingScheduleId)
      ).to.be.revertedWith("Ownable: caller is not the owner");
      await tokenVesting.revoke(vestingScheduleId);

      /*
       * TEST SUMMARY
       * deploy vesting contract
       * send tokens to vesting contract
       * create new vesting schedule (100 tokens)
       * check that vested amount is 0
       * set time to half the vesting period
       * check that vested amount is half the total amount to vest (50 tokens)
       * check that only beneficiary can try to release vested tokens
       * check that beneficiary cannot release more than the vested amount
       * release 10 tokens and check that a Transfer event is emitted with a value of 10
       * check that the released amount is 10
       * check that the vested amount is now 40
       * set current time after the end of the vesting period
       * check that the vested amount is 90 (100 - 10 released tokens)
       * release all vested tokens (90)
       * check that the number of released tokens is 100
       * check that the vested amount is 0
       * check that anyone cannot revoke a vesting
       */
    });

    it("Should release vested tokens if revoked", async function () {
      // send tokens to vesting contract
      await expect(testToken.transfer(tokenVesting.address, 1000))
        .to.emit(testToken, "Transfer")
        .withArgs(owner.address, tokenVesting.address, 1000);

      const beneficiary = addr1;
      const schedule: TokenVesting.VestingScheduleStruct = {
        initialized: true,
        revocable,
        revoked: false,
        beneficiary: beneficiary.address,
        start: startTime,
        cliff: startTime + cliff,
        duration,
        amountTotal,
        released: 0,
      };
      // create new vesting schedule
      await tokenVesting.createVestingSchedule(schedule);

      // compute vesting schedule id
      const vestingScheduleId =
        await tokenVesting.computeVestingScheduleIdForAddressAndIndex(
          beneficiary.address,
          0
        );

      // set time to half the vesting period
      const halfTime = baseTime + duration / 2;
      await tokenVesting.setCurrentTime(halfTime);

      await expect(tokenVesting.revoke(vestingScheduleId))
        .to.emit(testToken, "Transfer")
        .withArgs(tokenVesting.address, beneficiary.address, 50);
    });

    it("Should compute vesting schedule index", async function () {
      const expectedVestingScheduleId =
        "0xa279197a1d7a4b7398aa0248e95b8fcc6cdfb43220ade05d01add9c5468ea097";
      expect(
        await tokenVesting.computeVestingScheduleIdForAddressAndIndex(
          addr1.address,
          0
        )
      ).to.equal(expectedVestingScheduleId);
      expect(
        await tokenVesting.computeNextVestingScheduleIdForHolder(addr1.address)
      ).to.equal(expectedVestingScheduleId);
    });

    it("Should check input parameters for createVestingSchedule method", async function () {
      await testToken.transfer(tokenVesting.address, 1000);
      const time = Math.round(Date.now() / 1000);
      await expect(
        tokenVesting.createVestingSchedule({
          initialized: true,
          revocable: false,
          revoked: false,
          beneficiary: addr1.address,
          start: time,
          cliff: time,
          duration: 0,
          amountTotal: 1,
          released: 0,
        } as TokenVesting.VestingScheduleStruct)
      ).to.be.revertedWithCustomError(tokenVesting, "InvalidDuration");
      await expect(
        tokenVesting.createVestingSchedule({
          initialized: true,
          revocable: false,
          revoked: false,
          beneficiary: addr1.address,
          start: time,
          cliff: time,
          duration: 1,
          amountTotal: 0,
          released: 0,
        } as TokenVesting.VestingScheduleStruct)
      ).to.be.revertedWithCustomError(tokenVesting, "InvalidAmount");
    });
  });
});
