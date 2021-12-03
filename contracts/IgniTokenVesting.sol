// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./library/Governance.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract IgniTokenVesting is Governance {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using SafeMath for uint16;

    IERC20 public token;

    event GrantAdded(
        address recipient,
        uint256 startTime,
        uint256 amount,
        uint256 vestingDuration
    );
    event GrantRemoved(
        address recipient,
        uint256 amountVested,
        uint256 amountNotVested
    );

    event GrantRecipientChange(address newrecipient);
    event GrantTokensClaimed(address recipient, uint256 amountClaimed);

    struct Grant {
        uint256 startTime;
        uint256 amount;
        uint256 vestingDuration;
        uint256 totalClaimed;
        address recipient;
    }
    mapping(uint256 => Grant) public tokenGrants;

    constructor(address _token) {
        token = IERC20(_token);
    }

    /// @notice Add a new token grant for user `_recipient`. Only one grant per user is allowed
    /// The amount of CLNY tokens here need to be preapproved for transfer by this `Vesting` contract before this call
    /// Secured to the Colony MultiSig only
    /// @param _recipient Address of the token grant recipient entitled to claim the grant funds
    /// @param _startTime Grant start time as seconds since unix epoch
    /// Allows backdating grants by passing time in the past. If `0` is passed here current blocktime is used.
    /// @param _amount Total number of tokens in grant
    /// @param _vestingDuration Number of months of the grant's duration
    function addTokenGrant(
        uint256 vestingId,
        address _recipient,
        uint256 _startTime,
        uint256 _amount,
        uint256 _vestingDuration
    ) public onlyGovernance {
        require(_amount > 0, "igni-token-zero-amount-vested");

        // Transfer the grant tokens under the control of the vesting contract
        token.transferFrom(msg.sender, address(this), _amount);

        Grant memory grant = Grant({
            startTime: _startTime == 0 ? block.timestamp : _startTime,
            amount: _amount,
            vestingDuration: _vestingDuration,
            totalClaimed: 0,
            recipient: _recipient
        });

        tokenGrants[vestingId] = grant;
        emit GrantAdded(_recipient, grant.startTime, _amount, _vestingDuration);
    }

    function changeRecipient(uint256 vestingId, address _newRecipient) public {
        Grant storage tokenGrant = tokenGrants[vestingId];
        require(
            tokenGrant.recipient == msg.sender || _governance == msg.sender,
            "only recipient"
        );
        tokenGrant.recipient = _newRecipient;

        emit GrantRecipientChange(_newRecipient);
    }

    /// @notice Allows a grant recipient to claim their vested tokens. Errors if no tokens have vested
    /// It is advised recipients check they are entitled to claim via `calculateGrantClaim` before calling this
    function claimVestedTokens(uint256 vestingId) public {
        uint256 amountVested = calculateGrantClaim(vestingId);

        require(amountVested > 0, "igni-token-zero-amount-vested");
        Grant storage tokenGrant = tokenGrants[vestingId];
        tokenGrant.totalClaimed = tokenGrant.totalClaimed.add(amountVested);

        require(
            token.transfer(tokenGrant.recipient, amountVested),
            "igni-token-sender-transfer-failed"
        );
        emit GrantTokensClaimed(tokenGrant.recipient, amountVested);
    }

    /// @notice Calculate the vested and unclaimed months and tokens available for `_recepient` to claim
    /// Due to rounding errors once grant duration is reached, returns the entire left grant amount
    function calculateGrantClaim(uint256 vestingId)
        public
        view
        returns (uint256)
    {
        Grant storage tokenGrant = tokenGrants[vestingId];

        if (block.timestamp < tokenGrant.startTime) {
            return 0;
        }

        if (
            block.timestamp >=
            tokenGrant.startTime.add(tokenGrant.vestingDuration)
        ) {
            return tokenGrant.amount.sub(tokenGrant.totalClaimed);
        } else {
            return
                tokenGrant
                    .amount
                    .mul(block.timestamp.sub(tokenGrant.startTime))
                    .div(tokenGrant.vestingDuration)
                    .sub(tokenGrant.totalClaimed);
        }
    }
}
