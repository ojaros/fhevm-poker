import axios from "axios";
import { ethers } from "hardhat";
import hre from "hardhat";

import type { Poker } from "../../types/contracts/Poker"
import { waitForBlock } from "../../utils/block";

export async function deployPokerFixture(): Promise<{ poker: Poker; address: string }> {
    const signers = await ethers.getSigners();
    console.log("SIGNER1 : ", signers[0])
    const admin = signers[0];    
    const pokerFactory = await ethers.getContractFactory("Poker");
    const poker = (await pokerFactory.connect(admin).deploy())
    const address = await poker.getAddress()

    return { poker, address };
}

export async function getTokensFromFaucet() {
    if (hre.network.name === "localfhenix") {
      const signers = await hre.ethers.getSigners();
  
      if ((await hre.ethers.provider.getBalance(signers[0].address)).toString() === "0") {
        console.log("Balance for signer is 0 - getting tokens from faucet");
        await axios.get(`http://localhost:6000/faucet?address=${signers[0].address}`);
        await waitForBlock(hre);
      }

      if ((await hre.ethers.provider.getBalance(signers[1].address)).toString() === "0") {
        console.log("Balance for signer is 0 - getting tokens from faucet");
        await axios.get(`http://localhost:6000/faucet?address=${signers[1].address}`);
        await waitForBlock(hre);
      }
    }
  }
