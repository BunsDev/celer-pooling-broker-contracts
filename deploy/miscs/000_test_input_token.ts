import * as dotenv from 'dotenv';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

dotenv.config();

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('InputTokenDummy', {
    from: deployer,
    log: true,
    args: [
      "USD Tether",
      "USDT",
      6,
      "10000000000000000000000000000"
    ]
  });
};

deployFunc.tags = ["TestInputToken"];
export default deployFunc;
