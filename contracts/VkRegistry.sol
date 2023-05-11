// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import {SnarkCommon} from "./crypto/SnarkCommon.sol";
import {Ownable} from "./Ownable.sol";

/*
 * Stores verifying keys for the circuits.
 * Each circuit has a signature which is its compile-time constants represented
 * as a uint256.
 */
contract VkRegistry is Ownable, SnarkCommon {
    mapping(uint256 => VerifyingKey) internal newkeyVks;
    mapping(uint256 => bool) internal newkeyVkSet;

    mapping(uint256 => VerifyingKey) internal deactivateVks;
    mapping(uint256 => bool) internal deactivateVkSet;

    mapping(uint256 => VerifyingKey) internal processVks;
    mapping(uint256 => bool) internal processVkSet;

    mapping(uint256 => VerifyingKey) internal tallyVks;
    mapping(uint256 => bool) internal tallyVkSet;

    //TODO: event for setVerifyingKeys

    function genDeactivateVkSig(
        uint256 _stateTreeDepth,
        uint256 _messageBatchSize
    ) public pure returns (uint256) {
        return (_stateTreeDepth << 64) + _messageBatchSize;
    }

    function genProcessVkSig(
        uint256 _stateTreeDepth,
        uint256 _voteOptionTreeDepth,
        uint256 _messageBatchSize
    ) public pure returns (uint256) {
        return
            (_messageBatchSize << 192) +
            (_stateTreeDepth << 128) +
            _voteOptionTreeDepth;
    }

    function genTallyVkSig(
        uint256 _stateTreeDepth,
        uint256 _intStateTreeDepth,
        uint256 _voteOptionTreeDepth
    ) public pure returns (uint256) {
        return
            (_stateTreeDepth << 128) +
            (_intStateTreeDepth << 64) +
            _voteOptionTreeDepth;
    }

    function setVerifyingKeys(
        uint256 _stateTreeDepth,
        uint256 _intStateTreeDepth,
        uint256 _messageBatchSize,
        uint256 _voteOptionTreeDepth,
        VerifyingKey memory _processVk,
        VerifyingKey memory _tallyVk,
        VerifyingKey memory _deactivateVk,
        VerifyingKey memory _newkeyVk
    ) public onlyOwner {
        uint256 deactivateVkSig = genDeactivateVkSig(
            _stateTreeDepth,
            _messageBatchSize
        );

        uint256 processVkSig = genProcessVkSig(
            _stateTreeDepth,
            _voteOptionTreeDepth,
            _messageBatchSize
        );

        uint256 tallyVkSig = genTallyVkSig(
            _stateTreeDepth,
            _intStateTreeDepth,
            _voteOptionTreeDepth
        );

        VerifyingKey storage newkeyVk = newkeyVks[_stateTreeDepth];
        newkeyVk.alpha1 = _newkeyVk.alpha1;
        newkeyVk.beta2 = _newkeyVk.beta2;
        newkeyVk.gamma2 = _newkeyVk.gamma2;
        newkeyVk.delta2 = _newkeyVk.delta2;
        // * DEV *
        delete newkeyVk.ic;
        for (uint8 i = 0; i < _newkeyVk.ic.length; i++) {
            newkeyVk.ic.push(_newkeyVk.ic[i]);
        }
        newkeyVkSet[_stateTreeDepth] = true;

        VerifyingKey storage deactivateVk = deactivateVks[deactivateVkSig];
        deactivateVk.alpha1 = _deactivateVk.alpha1;
        deactivateVk.beta2 = _deactivateVk.beta2;
        deactivateVk.gamma2 = _deactivateVk.gamma2;
        deactivateVk.delta2 = _deactivateVk.delta2;
        // * DEV *
        delete deactivateVk.ic;
        for (uint8 i = 0; i < _deactivateVk.ic.length; i++) {
            deactivateVk.ic.push(_deactivateVk.ic[i]);
        }
        deactivateVkSet[deactivateVkSig] = true;

        VerifyingKey storage processVk = processVks[processVkSig];
        processVk.alpha1 = _processVk.alpha1;
        processVk.beta2 = _processVk.beta2;
        processVk.gamma2 = _processVk.gamma2;
        processVk.delta2 = _processVk.delta2;
        // * DEV *
        delete processVk.ic;
        for (uint8 i = 0; i < _processVk.ic.length; i++) {
            processVk.ic.push(_processVk.ic[i]);
        }
        processVkSet[processVkSig] = true;

        VerifyingKey storage tallyVk = tallyVks[tallyVkSig];
        tallyVk.alpha1 = _tallyVk.alpha1;
        tallyVk.beta2 = _tallyVk.beta2;
        tallyVk.gamma2 = _tallyVk.gamma2;
        tallyVk.delta2 = _tallyVk.delta2;
        // * DEV *
        delete tallyVk.ic;
        for (uint8 i = 0; i < _tallyVk.ic.length; i++) {
            tallyVk.ic.push(_tallyVk.ic[i]);
        }
        tallyVkSet[tallyVkSig] = true;
    }

    function getNewkeyVkBy(
        uint256 _stateTreeDepth
    ) public view returns (VerifyingKey memory) {
        require(
            newkeyVkSet[_stateTreeDepth] == true,
            "VkRegistry: newkey verifying key not set"
        );

        return newkeyVks[_stateTreeDepth];
    }

    function getDeactivateVkBySig(
        uint256 _sig
    ) public view returns (VerifyingKey memory) {
        require(
            deactivateVkSet[_sig] == true,
            "VkRegistry: deactivate verifying key not set"
        );

        return deactivateVks[_sig];
    }

    function getDeactivateVk(
        uint256 _stateTreeDepth,
        uint256 _messageBatchSize
    ) public view returns (VerifyingKey memory) {
        uint256 sig = genDeactivateVkSig(_stateTreeDepth, _messageBatchSize);

        return getDeactivateVkBySig(sig);
    }

    function getProcessVkBySig(
        uint256 _sig
    ) public view returns (VerifyingKey memory) {
        require(
            processVkSet[_sig] == true,
            "VkRegistry: process verifying key not set"
        );

        return processVks[_sig];
    }

    function getProcessVk(
        uint256 _stateTreeDepth,
        uint256 _voteOptionTreeDepth,
        uint256 _messageBatchSize
    ) public view returns (VerifyingKey memory) {
        uint256 sig = genProcessVkSig(
            _stateTreeDepth,
            _voteOptionTreeDepth,
            _messageBatchSize
        );

        return getProcessVkBySig(sig);
    }

    function getTallyVkBySig(
        uint256 _sig
    ) public view returns (VerifyingKey memory) {
        require(
            tallyVkSet[_sig] == true,
            "VkRegistry: tally verifying key not set"
        );

        return tallyVks[_sig];
    }

    function getTallyVk(
        uint256 _stateTreeDepth,
        uint256 _intStateTreeDepth,
        uint256 _voteOptionTreeDepth
    ) public view returns (VerifyingKey memory) {
        uint256 sig = genTallyVkSig(
            _stateTreeDepth,
            _intStateTreeDepth,
            _voteOptionTreeDepth
        );

        return getTallyVkBySig(sig);
    }
}
