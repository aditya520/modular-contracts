// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

contract BeforeMintCallbackERC721 {

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error BeforeMintCallbackERC721NotImplemented();

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     *  @notice The beforeMintERC721 hook that is called by a core token before minting tokens.
     *
     *  @param _to The address that is minting tokens.
     *  @param _startTokenId The token ID being minted.
     *  @param _amount The amount of tokens to mint.
     *  @param _data Optional extra data passed to the hook.
     *  @return result Abi encoded bytes result of the hook.
     */
    function beforeMintERC721(address _to, uint256 _startTokenId, uint256 _amount, bytes memory _data)
        external
        payable
        virtual
        returns (bytes memory result)
    {
        revert BeforeMintCallbackERC721NotImplemented();
    }

}
