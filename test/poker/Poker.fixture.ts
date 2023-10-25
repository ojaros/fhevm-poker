import axios from "axios";
import { ethers } from "hardhat";
import hre from "hardhat";

import type { Poker } from "../../types/contracts/Poker"
import { waitForBlock } from "../../utils/block";
import { PokerChip } from "../../types";

export async function deployPokerFixture(): Promise<{ poker: Poker; pokerChip: PokerChip; address: string }> {
    const signers = await ethers.getSigners();
    const admin = signers[0];    
    const pokerFactory = await ethers.getContractFactory("Poker");
    const poker = (await pokerFactory.connect(admin).deploy())
    const pokerAddress = await poker.getAddress()

    const tokenFactory = await ethers.getContractFactory("PokerChip");
    const token = (await tokenFactory.connect(admin).deploy());
    const tokenAddress = await token.getAddress();

    return { poker, pokerChip: token, address: pokerAddress };
}

export async function getTokensFromFaucet() {
    if (hre.network.name === "localfhenix") {
      const signers = await hre.ethers.getSigners();
  
      if ((await hre.ethers.provider.getBalance(signers[0].address)).toString() === "0") {
        console.log("Balance for signer 0 is 0 - getting tokens from faucet");
        await axios.get(`http://localhost:6000/faucet?address=${signers[0].address}`);
        await waitForBlock(hre);
      }

      if ((await hre.ethers.provider.getBalance(signers[1].address)).toString() === "0") {
        console.log("Balance for signer 1 is 0 - getting tokens from faucet");
        await axios.get(`http://localhost:6000/faucet?address=${signers[1].address}`);
        await waitForBlock(hre);
      }

      if ((await hre.ethers.provider.getBalance(signers[2].address)).toString() === "0") {
        console.log("Balance for signer 2 is 0 - getting tokens from faucet");
        await axios.get(`http://localhost:6000/faucet?address=${signers[2].address}`);
        await waitForBlock(hre);
      }

      if ((await hre.ethers.provider.getBalance(signers[3].address)).toString() === "0") {
        console.log("Balance for signer 3 is 0 - getting tokens from faucet");
        await axios.get(`http://localhost:6000/faucet?address=${signers[3].address}`);
        await waitForBlock(hre);
      }

      if ((await hre.ethers.provider.getBalance(signers[4].address)).toString() === "0") {
        console.log("Balance for signer 4 is 0 - getting tokens from faucet");
        await axios.get(`http://localhost:6000/faucet?address=${signers[4].address}`);
        await waitForBlock(hre);
      }

      if ((await hre.ethers.provider.getBalance(signers[5].address)).toString() === "0") {
        console.log("Balance for signer 5 is 0 - getting tokens from faucet");
        await axios.get(`http://localhost:6000/faucet?address=${signers[5].address}`);
        await waitForBlock(hre);
      }

      if ((await hre.ethers.provider.getBalance(signers[6].address)).toString() === "0") {
        console.log("Balance for signer 6 is 0 - getting tokens from faucet");
        await axios.get(`http://localhost:6000/faucet?address=${signers[6].address}`);
        await waitForBlock(hre);
      }
    }
  }
