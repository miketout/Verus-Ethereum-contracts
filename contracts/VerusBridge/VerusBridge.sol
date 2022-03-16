// SPDX-License-Identifier: MIT
// Bridge between ethereum and verus

pragma solidity >=0.6.0 <0.9.0;
pragma experimental ABIEncoderV2;

import "../Libraries/VerusObjects.sol";
import "../Libraries/VerusConstants.sol";
import "./TokenManager.sol";
import "./VerusBridgeMaster.sol";
import "./VerusBridgeStorage.sol";
import "../MMR/VerusProof.sol";
import "./Token.sol";
import "./VerusSerializer.sol";
import "../VerusNotarizer/VerusNotarizer.sol";
import "./VerusCrossChainExport.sol";
import "./ExportManager.sol";

contract VerusBridge {

    TokenManager tokenManager;
    VerusSerializer verusSerializer;
    VerusProof verusProof;
    VerusNotarizer verusNotarizer;
    VerusCrossChainExport verusCCE;
    VerusBridgeMaster verusBridgeMaster;
    ExportManager exportManager;
    VerusBridgeStorage verusBridgeStorage;

    // Global storage is located in VerusBridgeStorage contract

    constructor(address verusBridgeMasterAddress, address verusBridgeStorageAddress,
                address tokenManagerAddress, address verusSerializerAddress, address verusProofAddress,
                address verusNotarizerAddress, address verusCCEAddress, address exportManagerAddress) {
        verusBridgeMaster = VerusBridgeMaster(verusBridgeMasterAddress); 
        verusBridgeStorage = VerusBridgeStorage(verusBridgeStorageAddress); 
        tokenManager = TokenManager(tokenManagerAddress);
        verusSerializer = VerusSerializer(verusSerializerAddress);
        verusProof = VerusProof(verusProofAddress);
        verusNotarizer = VerusNotarizer(verusNotarizerAddress);
        verusCCE = VerusCrossChainExport(verusCCEAddress);
        exportManager = ExportManager(exportManagerAddress);

    }

    function setContracts(address[] memory contracts) public {

        assert(msg.sender == address(verusBridgeMaster));

        if(contracts[uint(VerusConstants.ContractType.TokenManager)] != address(tokenManager))
            tokenManager = TokenManager(contracts[uint(VerusConstants.ContractType.TokenManager)]);
        
        if(contracts[uint(VerusConstants.ContractType.VerusSerializer)] != address(verusSerializer))
            verusSerializer = VerusSerializer(contracts[uint(VerusConstants.ContractType.VerusSerializer)]);
        
        if(contracts[uint(VerusConstants.ContractType.VerusProof)] != address(verusProof))    
            verusProof = VerusProof(contracts[uint(VerusConstants.ContractType.VerusProof)]);

        if(contracts[uint(VerusConstants.ContractType.VerusNotarizer)] != address(verusNotarizer))     
            verusNotarizer = VerusNotarizer(contracts[uint(VerusConstants.ContractType.VerusNotarizer)]);

        if(contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)] != address(verusCCE))     
            verusCCE = VerusCrossChainExport(contracts[uint(VerusConstants.ContractType.VerusCrossChainExport)]);

        if(contracts[uint(VerusConstants.ContractType.ExportManager)] != address(exportManager))     
            exportManager = ExportManager(contracts[uint(VerusConstants.ContractType.ExportManager)]);

    }
 
    function export(VerusObjects.CReserveTransfer memory transfer, uint256 paidValue) public payable {

        uint256 fees;

        fees = exportManager.checkExport(transfer, msg.value);

        assert(fees != 0); 

        if (transfer.currencyvalue.currency != VerusConstants.VEth) {

            verusBridgeStorage.addToFeesHeld(paidValue);
            Token token = Token(verusBridgeStorage.getERCMapping(transfer.currencyvalue.currency).erc20ContractAddress); 
            uint256 allowedTokens = token.allowance(msg.sender,address(this));
            uint256 tokenAmount = tokenManager.convertFromVerusNumber(transfer.currencyvalue.amount, token.decimals()); //convert to wei from verus satoshis
            assert( allowedTokens >= tokenAmount);
            //transfer the tokens to this contract
            token.transferFrom(msg.sender,address(this),tokenAmount); 
            token.approve(address(tokenManager),tokenAmount);
            //give an approval for the tokenmanagerinstance to spend the tokens
            tokenManager.exportERC20Tokens(transfer.currencyvalue.currency, tokenAmount);  //total amount kept as wei until export to verus

        } else if (transfer.flags & VerusConstants.CTRX_CURRENCY_EXPORT_FLAG == VerusConstants.CTRX_CURRENCY_EXPORT_FLAG){
            
            verusBridgeStorage.addToFeesHeld(paidValue);

           //TODO: Add handle ERC721 here

           /* Token token = Token(verusBridgeStorage.getERCMapping(transfer.currencyvalue.currency).erc20ContractAddress); 
            uint256 allowedTokens = token.allowance(msg.sender,address(this));
            uint256 tokenAmount = tokenManager.convertFromVerusNumber(transfer.currencyvalue.amount, token.decimals()); //convert to wei from verus satoshis
            assert( allowedTokens >= tokenAmount);
            //transfer the tokens to this contract
            token.transferFrom(msg.sender,address(this),tokenAmount); 
            token.approve(address(tokenManager),tokenAmount);
            //give an approval for the tokenmanagerinstance to spend the tokens
            tokenManager.exportERC20Tokens(transfer.currencyvalue.currency, tokenAmount);  //total amount kept as wei until export to verus */

        } else {
            //handle a vEth transfer
            transfer.currencyvalue.amount = uint64(tokenManager.convertToVerusNumber(msg.value - VerusConstants.transactionFee,18));
            verusBridgeStorage.addToEthHeld(msg.value - fees);  // msg.value == fees + amount in transaction checked in checkExport()
            verusBridgeStorage.addToFeesHeld(fees); //TODO: what happens if they send to much fee?
        } 
        _createExports(transfer);
    }

    function _createExports(VerusObjects.CReserveTransfer memory newTransaction) private {
        uint currentHeight = block.number;

        //check if the current block height has a set of transfers associated with it if so add to the existing array

        verusBridgeStorage.setReadyExportTransfers(currentHeight, newTransaction);

        bool bridgeReady = verusBridgeMaster.poolAvailable(VerusConstants.VerusBridgeAddress);

        bytes memory serializedCCE = verusSerializer.serializeCCrossChainExport(verusCCE.generateCCE(verusBridgeStorage.getReadyExports(currentHeight).transfers, bridgeReady));

        verusBridgeStorage.setReadyExportTxid(currentHeight, keccak256(abi.encodePacked(serializedCCE, verusBridgeStorage.getReadyExports(currentHeight).txidhash)));

    }

    /***
     * Import from Verus functions
     ***/
    function checkImports(bytes32[] memory _imports) public view returns(bytes32[] memory) {
        //loop through the transfers and return a list of unprocessed
        bytes32[] memory txidList = new bytes32[](_imports.length);
        uint iterator;
        for(uint i = 0; i < _imports.length; i++){
            if(verusBridgeStorage.processedTxids(_imports[i]) != true){
                txidList[iterator] = _imports[i];
                iterator++;
            }
        }
        return txidList;
    }

    function submitImports(VerusObjects.CReserveTransferImport[] memory _imports) public {
        //loop through the transfers and process
        for(uint i = 0; i < _imports.length; i++){
           _createImports(_imports[i]);
        }
    }


    function _createImports(VerusObjects.CReserveTransferImport memory _import) public returns(bool) {

        bytes32 txidfound;
        bytes memory sliced = _import.partialtransactionproof.components[0].elVchObj;

        assembly {
            txidfound := mload(add(sliced, 32))                                 // skip memory length (ETH encoded in an efficient 32 bytes ;) )
        }
        if (verusBridgeStorage.processedTxids(txidfound) == true) return false; 

        bool proven = verusProof.proveImports(_import);

        assert(proven);
        verusBridgeStorage.setProcessedTxids(txidfound);

        if (verusBridgeStorage.lastTxImportHeight() < _import.height)
            verusBridgeStorage.setlastTxImportHeight(_import.height);

        uint256 amount; 

        // check the transfers were in the hash.
        for(uint i = 0; i < _import.transfers.length; i++){
            // handle eth transactions
            amount = tokenManager.convertFromVerusNumber(uint256(_import.transfers[i].currencyvalue.amount),18);

            // if the transfer does not have the EXPORT_CURRENCY flag set
            if(_import.transfers[i].flags & VerusConstants.CTRX_CURRENCY_EXPORT_FLAG != VerusConstants.CTRX_CURRENCY_EXPORT_FLAG){
                    address destinationAddress;

                    bytes memory tempAddress  = _import.transfers[i].destination.destinationaddress;

                    assembly {
                    destinationAddress := mload(add(tempAddress, 20))
                    } 

                if(destinationAddress != address(0)){
                    if(_import.transfers[i].currencyvalue.currency == VerusConstants.VEth) {
                        // cast the destination as an ethAddress
                        assert(amount <= address(this).balance);
                            verusBridgeMaster.sendEth(amount, payable(destinationAddress));
                            verusBridgeStorage.subtractFromEthHeld(amount);
                            
                
                    } else {
                        // handle erc20 transactions  
                        // amount conversion is handled in token manager

                        tokenManager.importERC20Tokens(_import.transfers[i].currencyvalue.currency,
                            _import.transfers[i].currencyvalue.amount,
                            destinationAddress);
                    }
                }
            } else if(_import.transfers[i].destination.destinationtype & VerusConstants.DEST_REGISTERCURRENCY == VerusConstants.DEST_REGISTERCURRENCY) {
                     
                tokenManager.deployToken(_import.transfers[i].destination.destinationaddress);
                
            }
            //handle the distributions of the fees
            //add them into the fees array to be claimed by the message sender
            if(_import.transfers[i].fees > 0 && _import.transfers[i].feecurrencyid == VerusConstants.VEth){
                verusBridgeStorage.setClaimableFees(msg.sender,_import.transfers[i].fees);
            }
        }
        return true;
    }
    
    function getReadyExportsByBlock(uint _blockNumber) public view returns(VerusObjects.CReserveTransferSet memory) {
        //need a transferset for each position not each block
        //retrieve a block get the indexes, create a transfer set for each index add those to the array
        VerusObjects.CReserveTransferSet memory output = VerusObjects.CReserveTransferSet(
            _blockNumber,                     // position in array
            _blockNumber,               // blockHeight
            verusBridgeStorage.getReadyExports(_blockNumber).txidhash,  // cross chain export hash
            verusBridgeStorage.getReadyExports(_blockNumber).transfers       // list of CReserveTransfers
        );
        return output;
    }

    function getReadyExportsByRange(uint _startBlock,uint _endBlock) public view returns(VerusObjects.CReserveTransferSet[] memory returnedExports){
        //calculate the size that the return array will be to initialise it
        uint outputSize = 0;
        if(_startBlock < verusBridgeStorage.firstBlock()) _startBlock = verusBridgeStorage.firstBlock();
        for(uint i = _startBlock; i <= _endBlock; i++){
            if(verusBridgeStorage.getReadyExports(i).txidhash != bytes32(0))  outputSize += 1;
        }

        VerusObjects.CReserveTransferSet[] memory output = new VerusObjects.CReserveTransferSet[](outputSize);
        uint outputPosition = 0;
        for (uint blockNumber = _startBlock; blockNumber <= _endBlock; blockNumber++){
            if (verusBridgeStorage.getReadyExports(blockNumber).txidhash != bytes32(0)) {
                output[outputPosition] = getReadyExportsByBlock(blockNumber);
                outputPosition++;
            }
        }
        return output;      
    }



}
