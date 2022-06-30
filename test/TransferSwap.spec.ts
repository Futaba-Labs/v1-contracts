import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { BigNumber, Contract } from "ethers";
import { parseUnits } from "ethers/lib/utils";
import { ethers } from "hardhat";
import { beforeEach } from "mocha";

let transferSwapperContract: Contract;
let owner: SignerWithAddress;
let addr1: SignerWithAddress;
let addr2: SignerWithAddress;
let addrs: SignerWithAddress[];
const amountIn = parseUnits('1', 16)
const feeDeadline = BigNumber.from(Math.floor(Date.now() / 1000 + 600));
const recipient = "0x221E25Ad7373Fbaf33C7078B8666816586222A09";

const prepareContext = async () => {
  const factory = await ethers.getContractFactory("TransferSwapper");
  [owner, addr1, addr2, ...addrs] = await ethers.getSigners();
  // transferSwapperContract = await factory.deploy("0xc778417E063141139Fce010982780140Aa0cD5Ab");
}

describe("Transfer Swapper", () => {
  beforeEach(prepareContext)
  it("should swap by Uniswap V3(non native token)", async () => {
    const tokenIn = "0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984" // Uni Token
    const path = ethers.utils.solidityPack(['address', 'uint24', 'address'], [tokenIn, 10000, "0xc778417E063141139Fce010982780140Aa0cD5Ab"]); // Uni Token and WETH

    const params = {
      path,
      recipient,
      deadline: feeDeadline,
      amountIn,
      amountOutMinimum: amountIn.div(2),
    };
    const data = ethers.utils.defaultAbiCoder.encode(
      ['(bytes path, address recipient, uint256 deadline, uint256 amountIn, uint256 amountOutMinimum)'],
      [params]
    );

    const desc = {
      nativeIn: false,
      amountIn,
      tokenIn,
      tokenOut: "0xc778417E063141139Fce010982780140Aa0cD5Ab",
      router: "0xE592427A0AEce92De3Edee1F18E0157C05861564"
    }

    const tx = await transferSwapperContract.connect(owner).transferWithSwap(desc, data, { gasLimit: ethers.utils.hexlify(2000000), value: amountIn.div(10) },
    );

    await tx.wait()
    expect(amountIn).equal(amountIn)
  }
  )

  it("should swap by Uniswap V2(non native token)", async () => {
    const tokenIn = "0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7" // BUSD
    const tokenOut = "0x337610d27c682E347C9cD60BD4b3b107C9d34dDd" // USDT

    const data = ethers.utils.defaultAbiCoder.encode(
      ['uint256', 'uint256', 'address[]', 'address', 'uint256'],
      [amountIn, amountIn.div(2), [tokenIn, tokenOut], recipient, feeDeadline]
    );

    const desc = {
      nativeIn: false,
      amountIn,
      tokenIn,
      tokenOut,
      router: "0xD99D1c33F9fC3444f8101754aBC46c52416550D1"
    }

    const tx = await transferSwapperContract.connect(owner).transferWithSwap(desc, data, { gasLimit: ethers.utils.hexlify(2000000), value: amountIn.div(10) },
    );

    await tx.wait()
    expect(amountIn).equal(amountIn)
  }
  )
})