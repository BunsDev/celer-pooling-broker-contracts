import * as dotenv from 'dotenv';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

dotenv.config();

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('ShareToken', {
    from: deployer,
    log: true,
    args: [
      process.env.SHARE_TOKEN_NAME,
      process.env.SHARE_TOKEN_SYMBOL,
      process.env.SHARE_TOKEN_DECIMALS,
      process.env.BROKER
    ]
  });
};

deployFunc.tags = ['ShareToken'];
deployFunc.dependencies = [];
export default deployFunc;
