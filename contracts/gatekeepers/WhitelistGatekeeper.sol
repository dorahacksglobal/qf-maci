// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import { Ownable } from "../Ownable.sol";
import { SignUpGatekeeper } from './SignUpGatekeeper.sol';


contract WhitelistGatekeeper is SignUpGatekeeper, Ownable {
    address public maci;

    mapping (address => bool) public whitelist;
    mapping (address => bool) public registered;

    constructor() Ownable() {}

    function setWhiteList(address[] memory _users) public onlyOwner {
        for (uint256 i = 0; i < _users.length; i++) {
            whitelist[_users[i]] = true;
        }
    }

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
    function register(address user, bytes memory) public override returns (bool, uint256) {
        require(maci == msg.sender, "WhitelistGatekeeper: only specified MACI instance can call this function");
        require(whitelist[user], "WhitelistGatekeeper: not authorized");
        require(!registered[user], "WhitelistGatekeeper: registered");
        registered[user] = true;
        return (true, 100);
    }
}
