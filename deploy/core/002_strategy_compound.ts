import * as dotenv from 'dotenv';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

dotenv.config();

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('StrategyCompound', {
    from: deployer,
    log: true,
    args: [
      process.env.BROKER,
      process.env.COMP,
      process.env.UNISWAP,
      process.env.WETH
    ]
  });
};

deployFunc.tags = ['StComp'];
deployFunc.dependencies = [];
export default deployFunc;
