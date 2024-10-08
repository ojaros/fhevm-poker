import type { SignerWithAddress } from "@nomicfoundation/hardhat-ethers/dist/src/signer-with-address";

import type { Counter } from "../types";
import type { FheContract } from "../utils/instance";

type Fixture<T> = () => Promise<T>;

declare module "mocha" {
  export interface Context {
    counter: Counter;
    instance: FheContract;
    loadFixture: <T>(fixture: Fixture<T>) => Promise<T>;
    signers: Signers;
  }
}

export interface Signers {
  admin: SignerWithAddress;
  player1: SignerWithAddress;
  player2: SignerWithAddress;
  player3: SignerWithAddress;
  player4: SignerWithAddress;
  player5: SignerWithAddress;
  player6: SignerWithAddress;
}
