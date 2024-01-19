// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import {IERC7572} from "../interface/eip/IERC7572.sol";
import {IERC20CoreCustomErrors} from "../interface/erc20/IERC20CoreCustomErrors.sol";
import {IERC20Hook} from "../interface/erc20/IERC20Hook.sol";
import {IERC20HookInstaller} from "../interface/erc20/IERC20HookInstaller.sol";
import {ERC20Initializable} from "./ERC20Initializable.sol";
import {HookInstaller} from "../extension/HookInstaller.sol";
import {Initializable} from "../extension/Initializable.sol";
import {Permission} from "../extension/Permission.sol";

contract ERC721Core is Initializable, ERC20Initializable, HookInstaller, Permission, IERC20HookInstaller, IERC20CoreCustomErrors, IERC7572 {

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Bits representing the before mint hook.
    uint256 public constant BEFORE_MINT_FLAG = 2 ** 1;

    /// @notice Bits representing the before transfer hook.
    uint256 public constant BEFORE_TRANSFER_FLAG = 2 ** 2;

    /// @notice Bits representing the before burn hook.
    uint256 public constant BEFORE_BURN_FLAG = 2 ** 3;

    /// @notice Bits representing the before approve hook.
    uint256 public constant BEFORE_APPROVE_FLAG = 2 ** 4;

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice The contract URI of the contract.
    string private _contractURI;
    
    /*//////////////////////////////////////////////////////////////
                    CONSTRUCTOR + INITIALIZE
    //////////////////////////////////////////////////////////////*/

    constructor() {
        _disableInitializers();
    }

    function initialize(address _defaultAdmin, string memory _name, string memory _symbol, string memory _uri) external initializer {
        _setupContractURI(_uri);
        __ERC20_init(_name, _symbol);
        _setupRole(_defaultAdmin, ADMIN_ROLE_BITS);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns all of the contract's hooks and their implementations.
    function getAllHooks() external view returns (ERC20Hooks memory hooks) {
        hooks = ERC20Hooks({
            beforeMint: getHookImplementation(BEFORE_MINT_FLAG),
            beforeTransfer: getHookImplementation(BEFORE_TRANSFER_FLAG),
            beforeBurn: getHookImplementation(BEFORE_BURN_FLAG),
            beforeApprove: getHookImplementation(BEFORE_APPROVE_FLAG)
        });
    }

    /**
     *  @notice Returns the contract URI of the contract.
     *  @return uri The contract URI of the contract.
     */
    function contractURI() external view override returns (string memory) {
        return _contractURI;
    }

    /*//////////////////////////////////////////////////////////////
                        EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice Sets the contract URI of the contract.
     *  @dev Only callable by contract admin.
     *  @param _uri The contract URI to set.
     */
    function setContractURI(string memory _uri) external onlyAuthorized(ADMIN_ROLE_BITS) {
        _setupContractURI(_uri);
    }

    function burn(uint256 _amount) external {

        _beforeBurn(msg.sender, _amount);
        _burn(msg.sender, _amount);
    }

    function mint(address _to, uint256 _amount, bytes memory _encodedBeforeMintArgs) external payable {
        IERC20Hook.MintParams memory mintParams = _beforeMint(_to, _amount, _encodedBeforeMintArgs);
        _mint(_to, mintParams.quantityToMint);
    }

    function transferFrom(address _from, address _to, uint256 _amount) public override returns(bool) {
        _beforeTransfer(_from, _to, _amount);
        return super.transferFrom(_from, _to, _amount);
    }

    function approve(address _spender, uint256 _amount) public override returns(bool) {
        _beforeApprove(msg.sender, _spender, _amount);
        return super.approve(_spender, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Sets contract URI
    function _setupContractURI(string memory _uri) internal {
        _contractURI = _uri;
        emit ContractURIUpdated();
    }

    /// @dev Returns whether the given caller can update hooks.
    function _canUpdateHooks(address _caller) internal view override returns (bool) {
        return hasRole(_caller, ADMIN_ROLE_BITS);
    }

    /// @dev Should return the max flag that represents a hook.
    function _maxHookFlag() internal pure override returns (uint256) {
        return BEFORE_APPROVE_FLAG;
    }

    /*//////////////////////////////////////////////////////////////
                        HOOKS INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @dev Calls the beforeMint hook.
    function _beforeMint(address _to, uint256 _amount, bytes memory _data)
        internal
        virtual
        returns (IERC20Hook.MintParams memory mintParams)
    {
        address hook = getHookImplementation(BEFORE_MINT_FLAG);

        if (hook != address(0)) {
            mintParams = IERC20Hook(hook).beforeMint{value: msg.value}(_to, _amount, _data);
        } else {
            revert ERC20CoreMintingDisabled();
        }
    }

    /// @dev Calls the beforeTransfer hook, if installed.
    function _beforeTransfer(address _from, address _to, uint256 _amount) internal virtual {
        address hook = getHookImplementation(BEFORE_TRANSFER_FLAG);

        if (hook != address(0)) {
            IERC20Hook(hook).beforeTransfer(_from, _to, _amount);
        }
    }

    /// @dev Calls the beforeBurn hook, if installed.
    function _beforeBurn(address _from, uint256 _amount) internal virtual {
        address hook = getHookImplementation(BEFORE_BURN_FLAG);

        if (hook != address(0)) {
            IERC20Hook(hook).beforeBurn(_from, _amount);
        }
    }

    /// @dev Calls the beforeApprove hook, if installed.
    function _beforeApprove(address _from, address _to, uint256 _amount) internal virtual {
        address hook = getHookImplementation(BEFORE_APPROVE_FLAG);

        if (hook != address(0)) {
            IERC20Hook(hook).beforeApprove(_from, _to, _amount);
        }
    }
}
