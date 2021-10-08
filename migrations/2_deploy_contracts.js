var VerusTokenManager = artifacts.require("./VerusBridge/TokenManager.sol");
var VerusBlake2b = artifacts.require("./MMR/VerusBlake2b.sol");
var VerusSerializer = artifacts.require("./VerusBridge/VerusSerializer.sol");
var VerusNotarizer = artifacts.require("./VerusNotarizer/VerusNotarizer.sol");
var VerusProof = artifacts.require("./MMR/VerusProof.sol");
var VerusCCE = artifacts.require("./VerusBridge/VerusCrossChainExport.sol");
var VerusBridge = artifacts.require("./VerusBridge/VerusBridge.sol");
var Verusaddress = artifacts.require("./VerusBridge/VerusAddressCalculator.sol");
var VerusInfo = artifacts.require("./VerusBridge/VerusInfo.sol");
var Token = artifacts.require("./VerusBridge/Token.sol");

const verusNotariserIDS = ["0xb26820ee0c9b1276aac834cf457026a575dfce84","0x51f9f5f053ce16cb7ca070f5c68a1cb0616ba624","0x65374d6a8b853a5f61070ad7d774ee54621f9638"];
const verusNotariserSigner = ["0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41","0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41","0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41"];
const tokenmanvrsctest = ["0xA6ef9ea235635E328124Ff3429dB9F9E91b64e2d","VRSCTEST","VRST"] 
const tokenmanUSDC = ["0xeb8f08a975ab53e34d8a0330e0d34de942c95926","0xf0a1263056c30e221f0f851c36b767fff2544f7f"]

const USDCERC20 = "0xeb8f08a975ab53e34d8a0330e0d34de942c95926";
const tokenmanbeth = ["0xffece948b8a38bbcc813411d2597f7f8485a0689","Bridge.veth","beth"] ;

const BLAKECONTRACT = "0x59d8F551F82c7164A22f481b6e35556bf43701C9"
const SERIALIZERCONTRACT = "0x86cA0e322d402124F8efD4dE76af5D44eeF4206d"
const TOKENMANAGERCONTRACT = "0x981F1120BcE46eC8cfeA3b604884f2a4918e88C4"

module.exports = async function (deployer) {
     
  //  await deployer.deploy(Verusaddress)
 //   const addressInst = await Verusaddress.deployed();

  //  await deployer.link(Verusaddress,VerusTokenManager );
  //  await deployer.deploy(VerusTokenManager)
    const tokenInst = await VerusTokenManager.at(TOKENMANAGERCONTRACT);
    
   // await deployer.deploy(VerusBlake2b);
  //  const blakeInst = await VerusBlake2b.deployed();
 
  //  await deployer.deploy(VerusSerializer);
  //  const serializerInst = await VerusSerializer.deployed();

  //  await tokenInst.deployNewToken(tokenmanvrsctest[0], tokenmanvrsctest[1], tokenmanvrsctest[2]); //registers VRSCTEST
  //  await tokenInst.deployNewToken(tokenmanbeth[0], tokenmanbeth[1], tokenmanbeth[2]); //registers VRSCTEST
  //  await tokenInst.addExistingToken(tokenmanUSDC[0], tokenmanUSDC[1]);  //registers USDC
 
    await deployer.deploy(VerusNotarizer, BLAKECONTRACT, SERIALIZERCONTRACT, verusNotariserIDS, verusNotariserSigner);
    const notarizerInst = await VerusNotarizer.deployed();

    await deployer.deploy(VerusProof,notarizerInst.address,BLAKECONTRACT,SERIALIZERCONTRACT);
    const ProofInst = await VerusProof.deployed();

    await deployer.deploy(VerusCCE,SERIALIZERCONTRACT);
    const CCEInst = await VerusCCE.deployed();
 
    await deployer.deploy(VerusBridge,ProofInst.address, TOKENMANAGERCONTRACT, SERIALIZERCONTRACT,
                              notarizerInst.address, CCEInst.address, "5000000000000000000000");
    const VerusBridgeInst = await VerusBridge.deployed();

    
    await deployer.deploy(VerusInfo, notarizerInst.address,"2000753","0.7.3-9-rc1","VETH",true);
    const INFOInst = await VerusInfo.deployed();

    let USDCInst = await Token.at(USDCERC20);

    USDCInst.increaseAllowance(VerusBridgeInst.address,"1000000000000000000000000")


};