import { ethers, BigNumber } from 'ethers'
import hre, { network } from "hardhat";

export const expandTo18Decimals = (n: number): BigNumber => {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(18))
}

export const expandToDecimals = (n: number, d: number): BigNumber => {
  return BigNumber.from(n).mul(BigNumber.from(10).pow(d))
}

export const buildBytecode = (
  constructorTypes: any[],
  constructorArgs: any[],
  contractBytecode: string
) =>
  `${contractBytecode}${encodeParams(constructorTypes, constructorArgs).slice(
    2
  )}`

export const buildCreate2Address = (
  address: string,
  saltHex: string,
  byteCode: string
) => {
  return `0x${ethers.utils
    .keccak256(
      `0x${['ff', address, saltHex, ethers.utils.keccak256(byteCode)]
        .map((x) => x.replace(/0x/, ''))
        .join('')}`
    )
    .slice(-40)}`.toLowerCase()
}

export const numberToUint256 = (value: number) => {
  const hex = value.toString(16)
  return `0x${'0'.repeat(64 - hex.length)}${hex}`
}

export const saltToHex = (salt: string | number) =>
  ethers.utils.id(salt.toString())

export const encodeParam = (dataType: any, data: any) => {
  const abiCoder = ethers.utils.defaultAbiCoder
  return abiCoder.encode([dataType], [data])
}

export const encodeParams = (dataTypes: any[], data: any[]) => {
  const abiCoder = ethers.utils.defaultAbiCoder
  return abiCoder.encode(dataTypes, data)
}

export const timeTravel = async (seconds: number) => {
  await network.provider.send("evm_increaseTime", [seconds]);
  await network.provider.send("evm_mine", []);
};

export const unlockAccount = async (address: string) => {
  await hre.network.provider.send("hardhat_impersonateAccount", [address]);
  return address;
}