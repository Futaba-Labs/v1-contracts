// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { ethers } from "hardhat";
import { bscData, bscTestnetData, polygonData, rinkebyData } from "./lib/consts";

async function main() {
  // Hardhat always runs the compile task when running scripts with its command
  // line interface.
  //
  // If this script is run directly using `node` you may want to call compile
  // manually to make sure everything is compiled
  // await hre.run('compile');

  // We get the contract to deploy
  const Swap = await ethers.getContractFactory("TransferSwapper");

  const router = rinkebyData.router
  const nativeToken = rinkebyData.nativeToken
  const swap = await Swap.deploy(nativeToken, router);

  await swap.deployed();

  console.log("deployed to:", swap.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
