// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Module} from "../../../Module.sol";

import {Role} from "../../../Role.sol";

import {IInstallationCallback} from "../../../interface/IInstallationCallback.sol";
import {IMintFeeManager} from "../../../interface/IMintFeeManager.sol";
import {OwnableRoles} from "@solady/auth/OwnableRoles.sol";
import {SafeTransferLib} from "@solady/utils/SafeTransferLib.sol";

import {BeforeMintCallbackERC20} from "../../../callback/BeforeMintCallbackERC20.sol";
import {BeforeMintWithSignatureCallbackERC20} from "../../../callback/BeforeMintWithSignatureCallbackERC20.sol";

interface IERC20 {

    function decimals() external view returns (uint8);

}

library MintableStorage {

    /// @custom:storage-location erc7201:token.minting.mintable
    bytes32 public constant MINTABLE_STORAGE_POSITION =
        keccak256(abi.encode(uint256(keccak256("token.minting.mintable.erc20")) - 1)) & ~bytes32(uint256(0xff));

    struct Data {
        // UID => whether it has been used
        mapping(bytes32 => bool) uidUsed;
        // sale config
        MintableERC20.SaleConfig saleConfig;
    }

    function data() internal pure returns (Data storage data_) {
        bytes32 position = MINTABLE_STORAGE_POSITION;
        assembly {
            data_.slot := position
        }
    }

}

contract MintableERC20 is
    Module,
    BeforeMintCallbackERC20,
    BeforeMintWithSignatureCallbackERC20,
    IInstallationCallback
{

    /*//////////////////////////////////////////////////////////////
                            STRUCTS & ENUMS
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice The request struct signed by an authorized party to mint tokens.
     *
     *  @param startTimestamp The timestamp at which the minting request is valid.
     *  @param endTimestamp The timestamp at which the minting request expires.
     *  @param currency The address of the currency used to pay for the minted tokens.
     *  @param pricePerUnit The price per unit of the minted tokens.
     *  @param uid A unique identifier for the minting request.
     */
    struct MintSignatureParamsERC20 {
        uint48 startTimestamp;
        uint48 endTimestamp;
        address currency;
        uint256 pricePerUnit;
        bytes32 uid;
    }

    /**
     *  @notice The configuration of a token's sale value distribution.
     *
     *  @param primarySaleRecipient The address that receives the primary sale value.
     */
    struct SaleConfig {
        address primarySaleRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted when an incorrect amount of native token is sent.
    error MintableIncorrectNativeTokenSent();

    /// @dev Emitted when the minting request has expired.
    error MintableRequestOutOfTimeWindow();

    /// @dev Emitted when the minting request UID has been reused.
    error MintableRequestUidReused();

    /// @dev Emitted when the minting request does not match the expected values.
    error MintableRequestMismatch();

    /// @dev Emitted when the minting request signature is unauthorized.
    error MintableRequestUnauthorized();

    /// @dev Emitted when the minting request signature is unauthorized.
    error MintableSignatureMintUnauthorized();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    address private constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public immutable mintFeeManager;

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _mintFeeManager) {
        mintFeeManager = _mintFeeManager;
    }

    /*//////////////////////////////////////////////////////////////
                            MODULE CONFIG
    //////////////////////////////////////////////////////////////*/

    function getModuleConfig() external pure override returns (ModuleConfig memory config) {
        config.callbackFunctions = new CallbackFunction[](2);
        config.fallbackFunctions = new FallbackFunction[](2);

        config.callbackFunctions[0] = CallbackFunction(this.beforeMintERC20.selector);
        config.callbackFunctions[1] = CallbackFunction(this.beforeMintWithSignatureERC20.selector);

        config.fallbackFunctions[0] = FallbackFunction({selector: this.getSaleConfig.selector, permissionBits: 0});
        config.fallbackFunctions[1] =
            FallbackFunction({selector: this.setSaleConfig.selector, permissionBits: Role._MANAGER_ROLE});

        config.requiredInterfaces = new bytes4[](1);
        config.requiredInterfaces[0] = 0x36372b07; // ERC20

        config.registerInstallationCallback = true;
    }

    /*//////////////////////////////////////////////////////////////
                            CALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Callback function for the ERC20Core.mint function.
    function beforeMintERC20(address _to, uint256 _amount, bytes memory _data)
        external
        payable
        virtual
        override
        returns (bytes memory)
    {
        if (!OwnableRoles(address(this)).hasAllRoles(msg.sender, Role._MINTER_ROLE)) {
            revert MintableRequestUnauthorized();
        }
    }

    /// @notice Callback function for the ERC20Core.mint function.
    function beforeMintWithSignatureERC20(address _to, uint256 _amount, bytes memory _data, address _signer)
        external
        payable
        virtual
        override
        returns (bytes memory)
    {
        if (!OwnableRoles(address(this)).hasAllRoles(_signer, Role._MINTER_ROLE)) {
            revert MintableSignatureMintUnauthorized();
        }

        MintSignatureParamsERC20 memory _params = abi.decode(_data, (MintSignatureParamsERC20));

        _mintWithSignatureERC20(_params);
        _distributeMintPrice(
            msg.sender, _params.currency, (_amount * _params.pricePerUnit) / (10 ** IERC20(address(this)).decimals())
        );
    }

    /// @dev Called by a Core into an Module during the installation of the Module.
    function onInstall(bytes calldata data) external {
        address primarySaleRecipient = abi.decode(data, (address));
        _mintableStorage().saleConfig = SaleConfig(primarySaleRecipient);
    }

    /// @dev Called by a Core into an Module during the uninstallation of the Module.
    function onUninstall(bytes calldata data) external {}

    /*//////////////////////////////////////////////////////////////
                    Encode install / uninstall data
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns bytes encoded install params, to be sent to `onInstall` function
    function encodeBytesOnInstall(address primarySaleRecipient) external pure returns (bytes memory) {
        return abi.encode(primarySaleRecipient);
    }

    /// @dev Returns bytes encoded uninstall params, to be sent to `onUninstall` function
    function encodeBytesOnUninstall() external pure returns (bytes memory) {
        return "";
    }

    /*//////////////////////////////////////////////////////////////
                        Encode mint params
    //////////////////////////////////////////////////////////////*/

    /// @dev Returns bytes encoded mint params, to be used in `beforeMintWithSignature` fallback function
    function encodeBytesBeforeMintWithSignatureERC20(MintSignatureParamsERC20 memory params)
        external
        pure
        returns (bytes memory)
    {
        return abi.encode(params);
    }

    /*//////////////////////////////////////////////////////////////
                            FALLBACK FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the sale configuration for a token.
    function getSaleConfig() external view returns (address primarySaleRecipient) {
        SaleConfig memory saleConfig = _mintableStorage().saleConfig;
        return (saleConfig.primarySaleRecipient);
    }

    /// @notice Sets the sale configuration for a token.
    function setSaleConfig(address _primarySaleRecipient) external {
        _mintableStorage().saleConfig = SaleConfig(_primarySaleRecipient);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Mints tokens on verifying a signature from an authorized party.
    function _mintWithSignatureERC20(MintSignatureParamsERC20 memory _req) internal {
        if (block.timestamp < _req.startTimestamp || _req.endTimestamp <= block.timestamp) {
            revert MintableRequestOutOfTimeWindow();
        }

        if (_mintableStorage().uidUsed[_req.uid]) {
            revert MintableRequestUidReused();
        }

        _mintableStorage().uidUsed[_req.uid] = true;
    }

    /// @dev Distributes the minting price to the primary sale recipient and platform fee recipient.
    function _distributeMintPrice(address _owner, address _currency, uint256 _price) internal {
        if (_price == 0) {
            if (msg.value > 0) {
                revert MintableIncorrectNativeTokenSent();
            }
            return;
        }

        SaleConfig memory saleConfig = _mintableStorage().saleConfig;

        if (_currency == NATIVE_TOKEN_ADDRESS) {
            if (msg.value != _price) {
                revert MintableIncorrectNativeTokenSent();
            }
            (uint256 platformFeeAmount, address feeRecipient) =
                IMintFeeManager(mintFeeManager).calculatePlatformFeeAndRecipient(_price);
            uint256 primarySaleAmount = _price - platformFeeAmount;
            SafeTransferLib.safeTransferETH(feeRecipient, platformFeeAmount);
            SafeTransferLib.safeTransferETH(saleConfig.primarySaleRecipient, primarySaleAmount);
        } else {
            if (msg.value > 0) {
                revert MintableIncorrectNativeTokenSent();
            }
            (uint256 platformFeeAmount, address feeRecipient) =
                IMintFeeManager(mintFeeManager).calculatePlatformFeeAndRecipient(_price);
            uint256 primarySaleAmount = _price - platformFeeAmount;
            SafeTransferLib.safeTransferFrom(_currency, _owner, feeRecipient, platformFeeAmount);
            SafeTransferLib.safeTransferFrom(_currency, _owner, saleConfig.primarySaleRecipient, primarySaleAmount);
        }
    }

    function _mintableStorage() internal pure returns (MintableStorage.Data storage) {
        return MintableStorage.data();
    }

}
