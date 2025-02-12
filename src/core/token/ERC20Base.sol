// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Core} from "../../Core.sol";

import {ERC20} from "@solady/tokens/ERC20.sol";
import {ECDSA} from "@solady/utils/ECDSA.sol";
import {EIP712} from "@solady/utils/EIP712.sol";
import {Multicallable} from "@solady/utils/Multicallable.sol";
import {ReentrancyGuard} from "@solady/utils/ReentrancyGuard.sol";

import {IERC20} from "../../interface/IERC20.sol";

import {BeforeApproveCallbackERC20} from "../../callback/BeforeApproveCallbackERC20.sol";
import {BeforeBurnCallbackERC20} from "../../callback/BeforeBurnCallbackERC20.sol";
import {BeforeMintCallbackERC20} from "../../callback/BeforeMintCallbackERC20.sol";
import {BeforeMintWithSignatureCallbackERC20} from "../../callback/BeforeMintWithSignatureCallbackERC20.sol";
import {BeforeTransferCallbackERC20} from "../../callback/BeforeTransferCallbackERC20.sol";

contract ERC20Base is ERC20, Multicallable, Core, EIP712 {

    using ECDSA for bytes32;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    bytes32 private constant TYPEHASH_SIGNATURE_MINT_ERC20 =
        keccak256("MintRequestERC20(address to,uint256 amount,bytes data)");

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The name of the token.
    string private name_;

    /// @notice The symbol of the token.
    string private symbol_;

    /// @notice The contract metadata URI of the contract.
    string private contractURI_;

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the contract URI is updated.
    event ContractURIUpdated();

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function _initialize(
        string memory _name,
        string memory _symbol,
        string memory _contractURI,
        address _owner,
        address[] memory _modules,
        bytes[] memory _moduleInstallData
    ) internal {
        // Set contract metadata
        name_ = _name;
        symbol_ = _symbol;
        _setupContractURI(_contractURI);
        _initializeOwner(_owner);

        // Install and initialize modules
        require(_modules.length == _moduleInstallData.length);
        for (uint256 i = 0; i < _modules.length; i++) {
            _installModule(_modules[i], _moduleInstallData[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the name of the token.
    function name() public view override returns (string memory) {
        return name_;
    }

    /// @notice Returns the symbol of the token.
    function symbol() public view override returns (string memory) {
        return symbol_;
    }

    /**
     *  @notice Returns the contract URI of the contract.
     *  @return uri The contract URI of the contract.
     */
    function contractURI() external view returns (string memory) {
        return contractURI_;
    }

    function getSupportedCallbackFunctions()
        public
        pure
        override
        returns (SupportedCallbackFunction[] memory supportedCallbackFunctions)
    {
        supportedCallbackFunctions = new SupportedCallbackFunction[](5);
        supportedCallbackFunctions[0] = SupportedCallbackFunction({
            selector: BeforeMintCallbackERC20.beforeMintERC20.selector,
            mode: CallbackMode.REQUIRED
        });
        supportedCallbackFunctions[1] = SupportedCallbackFunction({
            selector: BeforeMintWithSignatureCallbackERC20.beforeMintWithSignatureERC20.selector,
            mode: CallbackMode.REQUIRED
        });
        supportedCallbackFunctions[2] = SupportedCallbackFunction({
            selector: BeforeTransferCallbackERC20.beforeTransferERC20.selector,
            mode: CallbackMode.OPTIONAL
        });
        supportedCallbackFunctions[3] = SupportedCallbackFunction({
            selector: BeforeBurnCallbackERC20.beforeBurnERC20.selector,
            mode: CallbackMode.OPTIONAL
        });
        supportedCallbackFunctions[4] = SupportedCallbackFunction({
            selector: BeforeApproveCallbackERC20.beforeApproveERC20.selector,
            mode: CallbackMode.OPTIONAL
        });
    }

    /// @notice Returns whether a given interface is implemented by the contract.
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165 Interface ID for ERC165
            || interfaceId == 0xe8a3d485 // ERC-7572
            || interfaceId == 0x7f5828d0 // ERC-173
            || interfaceId == type(IERC20).interfaceId || _supportsInterfaceViaModules(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                          EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice Sets the contract URI of the contract.
     *  @dev Only callable by contract admin.
     *  @param contractURI The contract URI to set.
     */
    function setContractURI(string memory contractURI) external onlyOwner {
        _setupContractURI(contractURI);
    }

    /**
     *  @notice Mints tokens. Calls the beforeMint hook.
     *  @dev Reverts if beforeMint hook is absent or unsuccessful.
     *  @param to The address to mint the tokens to.
     *  @param amount The amount of tokens to mint.
     *  @param data ABI encoded data to pass to the beforeMintERC20 hook.
     */
    function mint(address to, uint256 amount, bytes calldata data) external payable {
        _beforeMint(to, amount, data);
        _mint(to, amount);
    }

    /**
     *  @notice Mints a token with a signature. Calls the beforeMint hook.
     *  @dev Reverts if beforeMint hook is absent or unsuccessful.
     *  @param to The address to mint the token to.
     *  @param amount The amount of tokens to mint.
     *  @param data ABI encoded data to pass to the beforeMint hook.
     *  @param signature The signature produced from signing the minting request.
     */
    function mintWithSignature(address to, uint256 amount, bytes calldata data, bytes memory signature)
        external
        payable
    {
        address signer = _hashTypedData(
            keccak256(abi.encode(TYPEHASH_SIGNATURE_MINT_ERC20, to, amount, keccak256(data)))
        ).recover(signature);

        _beforeMintWithSignature(to, amount, data, signer);
        _mint(to, amount);
    }

    /**
     *  @notice Burns tokens.
     *  @dev Calls the beforeBurn hook. Skips calling the hook if it doesn't exist.
     *  @param from The address to burn tokens from.
     *  @param amount The amount of tokens to burn.
     *  @param data ABI encoded arguments to pass to the beforeBurnERC20 hook.
     */
    function burn(address from, uint256 amount, bytes calldata data) external payable {
        _beforeBurn(from, amount, data);

        if (from != msg.sender) {
            _spendAllowance(from, msg.sender, amount);
        }

        _burn(from, amount);
    }

    /**
     *  @notice Transfers tokens to a recipient.
     *  @param to The address to transfer tokens to.
     *  @param amount The quantity of tokens to transfer.
     */
    function transfer(address to, uint256 amount) public override returns (bool) {
        _beforeTransfer(msg.sender, to, amount);
        return super.transfer(to, amount);
    }

    /**
     *  @notice Transfers tokens from a sender to a recipient.
     *  @param from The address to transfer tokens from.
     *  @param to The address to transfer tokens to.
     *  @param amount The quantity of tokens to transfer.
     */
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _beforeTransfer(from, to, amount);
        return super.transferFrom(from, to, amount);
    }

    /**
     *  @notice Approves a spender to spend tokens on behalf of an owner.
     *  @param spender The address to approve spending on behalf of the token owner.
     *  @param amount The quantity of tokens to approve.
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _beforeApprove(msg.sender, spender, amount);
        return super.approve(spender, amount);
    }

    /**
     * @notice Sets allowance based on token owner's signed approval.
     *
     * See https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     *
     *  @param owner The account approving the tokens
     *  @param spender The address to approve
     *  @param amount Amount of tokens to approve
     *  @param deadline Deadline after which the approval is no longer valid
     *  @param v Signature param
     *  @param r Signature param
     *  @param s Signature param
     */
    function permit(address owner, address spender, uint256 amount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        public
        override
    {
        _beforeApprove(owner, spender, amount);
        super.permit(owner, spender, amount, deadline, v, r, s);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Sets contract URI
    function _setupContractURI(string memory _contractURI) internal {
        contractURI_ = _contractURI;
        emit ContractURIUpdated();
    }

    /*//////////////////////////////////////////////////////////////
                          CALLBACK INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Calls the beforeMint hook.
    function _beforeMint(address to, uint256 amount, bytes calldata data) internal virtual {
        _executeCallbackFunction(
            BeforeMintCallbackERC20.beforeMintERC20.selector,
            abi.encodeCall(BeforeMintCallbackERC20.beforeMintERC20, (to, amount, data))
        );
    }

    /// @dev Calls the beforeMint hook.
    function _beforeMintWithSignature(address to, uint256 amount, bytes calldata data, address signer)
        internal
        virtual
    {
        _executeCallbackFunction(
            BeforeMintWithSignatureCallbackERC20.beforeMintWithSignatureERC20.selector,
            abi.encodeCall(
                BeforeMintWithSignatureCallbackERC20.beforeMintWithSignatureERC20, (to, amount, data, signer)
            )
        );
    }

    /// @dev Calls the beforeTransfer hook, if installed.
    function _beforeTransfer(address from, address to, uint256 amount) internal virtual {
        _executeCallbackFunction(
            BeforeTransferCallbackERC20.beforeTransferERC20.selector,
            abi.encodeCall(BeforeTransferCallbackERC20.beforeTransferERC20, (from, to, amount))
        );
    }

    /// @dev Calls the beforeBurn hook, if installed.
    function _beforeBurn(address from, uint256 amount, bytes calldata data) internal virtual {
        _executeCallbackFunction(
            BeforeBurnCallbackERC20.beforeBurnERC20.selector,
            abi.encodeCall(BeforeBurnCallbackERC20.beforeBurnERC20, (from, amount, data))
        );
    }

    /// @dev Calls the beforeApprove hook, if installed.
    function _beforeApprove(address from, address to, uint256 amount) internal virtual {
        _executeCallbackFunction(
            BeforeApproveCallbackERC20.beforeApproveERC20.selector,
            abi.encodeCall(BeforeApproveCallbackERC20.beforeApproveERC20, (from, to, amount))
        );
    }

    /// @dev Returns the domain name and version for EIP712.
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "ERC20Core";
        version = "1";
    }

}
