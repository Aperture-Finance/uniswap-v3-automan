// contracts/TokenVesting.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "solmate/src/utils/SafeTransferLib.sol";

/**
 * @title TokenVesting
 * @author Aperture Finance
 */
contract TokenVesting is Ownable {
    using SafeTransferLib for ERC20;

    struct VestingSchedule {
        // first slot
        // whether or not the vesting schedule has been initialized
        bool initialized;
        // whether or not the vesting is revocable
        bool revocable;
        // whether or not the vesting has been revoked
        bool revoked;
        // beneficiary of tokens after they are released
        address beneficiary;
        // start time of the vesting period, latest year 2106
        uint32 start;
        // cliff in seconds, latest year 2106
        uint32 cliff;
        // second slot
        // duration of the vesting period in seconds, max 136 years
        uint32 duration;
        // total amount of tokens to be released at the end of the vesting
        uint112 amountTotal;
        // amount of tokens released
        uint112 released;
    }

    // address of the ERC20 token
    ERC20 private immutable token;

    bytes32[] private vestingSchedulesIds;
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    uint256 private vestingSchedulesTotalAmount;
    mapping(address => uint256) private holdersVestingCount;

    event Created(
        bytes32 indexed vestingScheduleId,
        address indexed beneficiary,
        uint112 amountTotal
    );
    event Released(
        bytes32 indexed vestingScheduleId,
        address indexed beneficiary,
        uint112 amount
    );
    event Revoked(bytes32 indexed vestingScheduleId, uint112 remainingAmount);
    event Withdrawn(address indexed owner, uint256 amount);

    error IndexOutOfBounds();
    error NotVesting();
    error NotRevocable();
    error NotWithdrawable();
    error InvalidAmount();
    error InvalidBeneficiary();
    error InvalidDuration();
    error InvalidCliff();
    error OnlyBeneficiaryOrOwner();

    /**
     * @dev Creates a vesting contract.
     * @param _token address of the ERC20 token contract
     */
    constructor(address _token) {
        require(_token != address(0));
        token = ERC20(_token);
    }

    /************************************************
     *  ACCESS CONTROL
     ***********************************************/

    function _onlyIfVestingScheduleExists(
        bytes32 vestingScheduleId
    ) private view {
        require(vestingSchedules[vestingScheduleId].initialized);
    }

    /**
     * @dev Reverts if no vesting schedule matches the passed identifier.
     */
    modifier onlyIfVestingScheduleExists(bytes32 vestingScheduleId) {
        _onlyIfVestingScheduleExists(vestingScheduleId);
        _;
    }

    function _onlyIfVestingScheduleNotRevoked(
        bytes32 vestingScheduleId
    ) private view {
        VestingSchedule storage vestingSchedule = vestingSchedules[
            vestingScheduleId
        ];
        require(vestingSchedule.initialized);
        require(!vestingSchedule.revoked);
    }

    /**
     * @dev Reverts if the vesting schedule does not exist or has been revoked.
     */
    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        _onlyIfVestingScheduleNotRevoked(vestingScheduleId);
        _;
    }

    /************************************************
     *  GETTERS
     ***********************************************/

    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Returns the address of the ERC20 token managed by the vesting contract.
     */
    function getToken() external view returns (address) {
        return address(token);
    }

    /**
     * @dev Returns the vesting schedule id at the given index.
     * @return the vesting id
     */
    function getVestingIdAtIndex(
        uint256 index
    ) external view returns (bytes32) {
        if (index >= vestingSchedulesIds.length) revert IndexOutOfBounds();
        return vestingSchedulesIds[index];
    }

    /**
     * @notice Returns the vesting schedule information for a given identifier.
     * @return the vesting schedule structure information
     */
    function getVestingSchedule(
        bytes32 vestingScheduleId
    ) public view returns (VestingSchedule memory) {
        return vestingSchedules[vestingScheduleId];
    }

    /**
     * @dev Returns the number of vesting schedules managed by this contract.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCount() external view returns (uint256) {
        return vestingSchedulesIds.length;
    }

    /**
     * @notice Returns the total amount of vesting schedules.
     * @return the total amount of vesting schedules
     */
    function getVestingSchedulesTotalAmount() external view returns (uint256) {
        return vestingSchedulesTotalAmount;
    }

    /**
     * @dev Returns the number of vesting schedules associated to a beneficiary.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCountByBeneficiary(
        address _beneficiary
    ) external view returns (uint256) {
        return holdersVestingCount[_beneficiary];
    }

    /**
     * @notice Returns the vesting schedule information for a given holder and index.
     * @return the vesting schedule structure information
     */
    function getVestingScheduleByAddressAndIndex(
        address holder,
        uint256 index
    ) external view returns (VestingSchedule memory) {
        return
            getVestingSchedule(
                computeVestingScheduleIdForAddressAndIndex(holder, index)
            );
    }

    /**
     * @dev Returns the last vesting schedule for a given holder address.
     */
    function getLastVestingScheduleForHolder(
        address holder
    ) external view returns (VestingSchedule memory) {
        uint256 count = holdersVestingCount[holder];
        if (count == 0) revert NotVesting();
        unchecked {
            return
                vestingSchedules[
                    computeVestingScheduleIdForAddressAndIndex(
                        holder,
                        count - 1
                    )
                ];
        }
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the owner.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() public view returns (uint256) {
        return token.balanceOf(address(this)) - vestingSchedulesTotalAmount;
    }

    /**
     * @notice Computes the vested amount of tokens for the given vesting schedule identifier.
     * @return the vested amount
     */
    function computeReleasableAmount(
        bytes32 vestingScheduleId
    )
        external
        view
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
        returns (uint256)
    {
        return _computeReleasableAmount(vestingSchedules[vestingScheduleId]);
    }

    /**
     * @dev Computes the vesting schedule identifier for an address and an index.
     */
    function computeVestingScheduleIdForAddressAndIndex(
        address holder,
        uint256 index
    ) public pure returns (bytes32 id) {
        assembly ("memory-safe") {
            mstore(0, holder)
            mstore(0x20, index)
            id := keccak256(12, 52)
        }
    }

    /**
     * @dev Computes the next vesting schedule identifier for a given holder address.
     */
    function computeNextVestingScheduleIdForHolder(
        address holder
    ) public view returns (bytes32) {
        return
            computeVestingScheduleIdForAddressAndIndex(
                holder,
                holdersVestingCount[holder]
            );
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule.
     * @return the amount of releasable tokens
     */
    function _computeReleasableAmount(
        VestingSchedule storage vestingSchedule
    ) internal view returns (uint112) {
        uint256 currentTime = getCurrentTime();
        unchecked {
            if (
                (currentTime < vestingSchedule.cliff) || vestingSchedule.revoked
            ) {
                return 0;
            } else if (
                currentTime >= vestingSchedule.start + vestingSchedule.duration
            ) {
                return vestingSchedule.amountTotal - vestingSchedule.released;
            } else {
                // start + duration > currentTime >= cliff >= start
                uint256 timeFromStart = currentTime - vestingSchedule.start;
                // duration > timeFromStart >= 0
                // uint112 * uint32 < uint256, cannot overflow
                uint256 vestedAmount = (vestingSchedule.amountTotal *
                    timeFromStart) / vestingSchedule.duration;
                return uint112(vestedAmount) - vestingSchedule.released;
            }
        }
    }

    /**
     * @notice Batch create vesting schedules.
     * @param _vestingSchedules vesting schedules to create
     */
    function batchCreateVestingSchedule(
        VestingSchedule[] calldata _vestingSchedules
    ) public onlyOwner {
        unchecked {
            uint256 _vestingSchedulesTotalAmount = vestingSchedulesTotalAmount;
            uint256 totalAmount = _vestingSchedulesTotalAmount;
            uint256 length = _vestingSchedules.length;
            for (uint256 i = 0; i < length; ++i) {
                VestingSchedule calldata vestingSchedule = _vestingSchedules[i];
                require(vestingSchedule.initialized);
                require(!vestingSchedule.revoked);
                require(vestingSchedule.released == 0);
                address beneficiary = vestingSchedule.beneficiary;
                if (beneficiary == address(0)) revert InvalidBeneficiary();
                uint112 amount = vestingSchedule.amountTotal;
                if (amount == 0) revert InvalidAmount();
                totalAmount += amount;
                {
                    uint32 start = vestingSchedule.start;
                    uint32 duration = vestingSchedule.duration;
                    uint32 end = start + duration;
                    if (duration == 0 || end < start) revert InvalidDuration();
                    uint32 cliff = vestingSchedule.cliff;
                    if (cliff < start || cliff > end) revert InvalidCliff();
                }
                bytes32 vestingScheduleId = computeNextVestingScheduleIdForHolder(
                        beneficiary
                    );
                vestingSchedules[vestingScheduleId] = vestingSchedule;
                vestingSchedulesIds.push(vestingScheduleId);
                ++holdersVestingCount[beneficiary];
                emit Created(vestingScheduleId, beneficiary, amount);
            }
            require(totalAmount > _vestingSchedulesTotalAmount);
            vestingSchedulesTotalAmount = totalAmount;
        }
    }

    /**
     * @notice Creates a new vesting schedule for a beneficiary.
     * @param vestingSchedule vesting schedule structure information
     */
    function createVestingSchedule(
        VestingSchedule calldata vestingSchedule
    ) external {
        VestingSchedule[] calldata _vestingSchedules;
        assembly {
            _vestingSchedules.length := 1
            _vestingSchedules.offset := vestingSchedule
        }
        batchCreateVestingSchedule(_vestingSchedules);
    }

    /**
     * @notice Revokes the vesting schedule for given identifier.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function revoke(
        bytes32 vestingScheduleId
    ) external onlyOwner onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        VestingSchedule storage vestingSchedule = vestingSchedules[
            vestingScheduleId
        ];
        if (!vestingSchedule.revocable) revert NotRevocable();
        uint112 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if (vestedAmount != 0) {
            release(vestingScheduleId, vestedAmount);
        }
        unchecked {
            uint112 remainingAmount = vestingSchedule.amountTotal -
                vestingSchedule.released;
            vestingSchedulesTotalAmount -= remainingAmount;
            vestingSchedule.revoked = true;
            emit Revoked(vestingScheduleId, remainingAmount);
        }
    }

    /**
     * @notice Withdraw the specified amount if possible.
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) external onlyOwner {
        if (getWithdrawableAmount() < amount) revert NotWithdrawable();
        token.safeTransfer(owner(), amount);
        emit Withdrawn(owner(), amount);
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     * @param amount the amount to release
     */
    function release(
        bytes32 vestingScheduleId,
        uint112 amount
    ) public onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        VestingSchedule storage vestingSchedule = vestingSchedules[
            vestingScheduleId
        ];
        address sender = msg.sender;
        address beneficiary = vestingSchedule.beneficiary;
        bool isBeneficiary = sender == beneficiary;
        bool isOwner = sender == owner();
        if (!isBeneficiary && !isOwner) revert OnlyBeneficiaryOrOwner();
        uint112 releasableAmount = _computeReleasableAmount(vestingSchedule);
        amount = releasableAmount < amount ? releasableAmount : amount;
        unchecked {
            // released + amount <= released + releasableAmount <= amountTotal
            vestingSchedule.released += amount;
            // vestingSchedulesTotalAmount >= amountTotal >= releasableAmount >= amount
            vestingSchedulesTotalAmount -= amount;
        }
        token.safeTransfer(beneficiary, amount);
        emit Released(vestingScheduleId, beneficiary, amount);
    }
}
