// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import { Ownable } from "../Ownable.sol";
import { SignUpGatekeeper } from './SignUpGatekeeper.sol';


contract SignUpSimpleGatekeeper is SignUpGatekeeper, Ownable {
    address public maci;

    mapping (address => bool) public registered;

    constructor() Ownable() {}

    /*
     * Adds an uninitialised MACI instance to allow for token singups
     * @param _maci The MACI contract interface to be stored
     */
    function setMaciInstance(address _maci) public onlyOwner override {
        maci = _maci;
    }

    /*
     * Registers the user if they own the token with the token ID encoded in
     * _data. Throws if the user is does not own the token or if the token has
     * already been used to sign up.
     * @param _user The user's Ethereum address.
     * @param _data The ABI-encoded tokenId as a uint256.
     */
    function register(address _user, bytes memory) public override returns (bool, uint256) {
        require(maci == msg.sender, "SignUpGatekeeper: only specified MACI instance can call this function");
        require(!registered[_user], "SignUpGatekeeper: registered");
        registered[_user] = true;
        return (true, 1000);
    }
}
