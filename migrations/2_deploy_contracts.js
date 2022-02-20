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

// QUESTION: remove all hard coded values like those below (tokenmanvrsctest, etc.) and put them in config or parameters
// What is the most correct approach / actual best practice?
const verusNotariserIDS = ["0xb26820ee0c9b1276aac834cf457026a575dfce84", "0x51f9f5f053ce16cb7ca070f5c68a1cb0616ba624", "0x65374d6a8b853a5f61070ad7d774ee54621f9638"];
const verusNotariserSigner = ["0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41", "0xD010dEBcBf4183188B00cafd8902e34a2C1E9f41"];
const tokenmanvrsctest = ["0x01000000880000000000000000000000000000000000000000000000087672736374657374a6ef9ea235635e328124ff3429db9f9e91b64e2d"]
const tokenmanbeth = ["0x010000008800000067460C2f56774eD27EeB8685f29f6CEC0B090B0006627269646765a6ef9ea235635e328124ff3429db9f9e91b64e2da6ef9ea235635e328124ff3429db9f9e91b64e2d"]
const tokenmanUSDC = ["0xeb8f08a975ab53e34d8a0330e0d34de942c95926", "0xf0a1263056c30e221f0f851c36b767fff2544f7f"]

const USDCERC20 = "0xeb8f08a975ab53e34d8a0330e0d34de942c95926";

module.exports = async function (deployer) {

    await deployer.deploy(Verusaddress)
    const addressInst = await Verusaddress.deployed();

    await deployer.link(Verusaddress, VerusTokenManager);
    
    await deployer.deploy(VerusBlake2b);
    const blakeInst = await VerusBlake2b.deployed();
    
    await deployer.deploy(VerusSerializer);
    const serializerInst = await VerusSerializer.deployed();

    await deployer.deploy(VerusTokenManager, serializerInst.address)
    const tokenInst = await VerusTokenManager.deployed();

    await tokenInst.deployNewToken(tokenmanvrsctest[0]); //registers VRSCTEST
    await tokenInst.deployNewToken(tokenmanbeth[0]); //registers bridge
    await tokenInst.addExistingToken(tokenmanUSDC[0], tokenmanUSDC[1]);  //registers USDC

    await deployer.deploy(VerusNotarizer, blakeInst.address, serializerInst.address, verusNotariserIDS, verusNotariserSigner);
    const notarizerInst = await VerusNotarizer.deployed();

    await deployer.deploy(VerusProof, notarizerInst.address, blakeInst.address, serializerInst.address);
    const ProofInst = await VerusProof.deployed();

    await deployer.deploy(VerusCCE, serializerInst.address);
    const CCEInst = await VerusCCE.deployed();

    await deployer.deploy(VerusBridge, ProofInst.address, tokenInst.address, serializerInst.address,
        notarizerInst.address, CCEInst.address, "5000000000000000000000");
    const VerusBridgeInst = await VerusBridge.deployed();

    await deployer.deploy(VerusInfo, notarizerInst.address, "2000753", "0.7.3-9-rc1", "VETH", true);
    const INFOInst = await VerusInfo.deployed();

    let USDCInst = await Token.at(USDCERC20);

    USDCInst.increaseAllowance(VerusBridgeInst.address, "1000000000000000000000000");

    const settingString = "verusbridgeaddress=" + VerusBridgeInst.address + "\n" +
    "verusnotarizeraddress=" + notarizerInst.address + "\n" +
    "verusproofaddress=" + ProofInst.address + "\n" +
    "verusinfoaddress=" + INFOInst.address + "\n" +
    "verusserializeraddress=" + serializerInst.address + "\n\n" +
    "{\"bridge\":\"" + VerusBridgeInst.address + "\",\n" +
    "\"notarizer\":\"" + notarizerInst.address + "\",\n" +
    "\"tokenmanager\":\"" + tokenInst.address + "\"}\n";

    console.log("Settings to be pasted into *.conf file (except the tokenmanger, thats for the bridge website) \n\n", settingString);
};