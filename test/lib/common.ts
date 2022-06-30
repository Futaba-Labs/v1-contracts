import { Wallet } from "ethers";
import { ethers } from "hardhat";
import { UniswapV2SwapExactTokensForTokensCodec, UniswapV2SwapExactTokensForTokensCodec__factory, UniswapV3ExactInputCodec, UniswapV3ExactInputCodec__factory } from "../../typechain";

export interface CodecContracts {
  v2Codec: UniswapV2SwapExactTokensForTokensCodec;
  v3Codec: UniswapV3ExactInputCodec;
}

export async function deployCodecContracts(admin: Wallet): Promise<CodecContracts> {
  const v2CodecFactory = (await ethers.getContractFactory(
    'UniswapV2SwapExactTokensForTokensCodec'
  )) as UniswapV2SwapExactTokensForTokensCodec__factory;
  const v2Codec = await v2CodecFactory.connect(admin).deploy();
  await v2Codec.deployed();

  const v3CodecFactory = (await ethers.getContractFactory(
    'UniswapV3ExactInputCodec'
  )) as UniswapV3ExactInputCodec__factory;
  const v3Codec = await v3CodecFactory.connect(admin).deploy();
  await v3Codec.deployed();

  return { v2Codec, v3Codec };
}