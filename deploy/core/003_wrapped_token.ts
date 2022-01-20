import * as dotenv from 'dotenv';
import { DeployFunction } from 'hardhat-deploy/types';
import { HardhatRuntimeEnvironment } from 'hardhat/types';

dotenv.config();

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy('WrappedToken', {
    from: deployer,
    log: true,
    args: [
      process.env.CTOKEN,
      process.env.ST_COMP,
      process.env.COMPTROLLER,
      process.env.COMP
    ]
  });
};

deployFunc.tags = ['WToken'];
deployFunc.dependencies = [];
export default deployFunc;
