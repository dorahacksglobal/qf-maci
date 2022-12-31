// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import {Ownable} from "../Ownable.sol";
import {SignUpGatekeeper} from "./SignUpGatekeeper.sol";

contract OracleGatekeeper is SignUpGatekeeper, Ownable {
    address public maci;

    address public signer;
    uint256 public roundSeq;

    mapping(address => bool) public registered;

    constructor(address _signer, uint256 _roundSeq) Ownable() {
        signer = _signer;
        roundSeq = _roundSeq;
    }

    /*
     * Adds an uninitialised MACI instance to allow for token singups
     * @param _maci The MACI contract interface to be stored
     */
    function setMaciInstance(address _maci) public override onlyOwner {
        maci = _maci;
    }

    /*
     * Registers the user if they own the token with the token ID encoded in
     * _data. Throws if the user is does not own the token or if the token has
     * already been used to sign up.
     * @param _user The user's Ethereum address.
     * @param _data The ABI-encoded tokenId as a uint256.
     */
    function register(address user, bytes calldata _sign)
        public
        override
        returns (bool, uint256)
    {
        require(
            maci == msg.sender,
            "OracleGatekeeper: only specified MACI instance can call this function"
        );
        bytes calldata sign = _sign[:65];
        uint256 balance = abi.decode(_sign[65:], (uint256));

        bytes32 h = keccak256(abi.encodePacked(maci, roundSeq, user, balance));
        uint8 v = uint8(bytes1(sign[64:]));
        (bytes32 r, bytes32 s) = abi.decode(sign[:64], (bytes32, bytes32));
        address recoverSigner = ecrecover(h, v, r, s);
        require(recoverSigner == signer, "OracleGatekeeper: invalid sign");

        require(!registered[user], "OracleGatekeeper: registered");
        registered[user] = true;
        uint256 votes = balance / 1e17;
        require(votes > 0);
        return (true, votes);
    }
}
