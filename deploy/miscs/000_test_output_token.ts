import * as dotenv from 'dotenv';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

dotenv.config();

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('OutputTokenDummy', {
    from: deployer,
    log: true,
    args: [
      process.env.INPUT_TOKEN_DUMMY,
      process.env.ST_DUMMY,
      100000000
    ]
  });
};

deployFunc.tags = ["TestOutputToken"];
export default deployFunc;
